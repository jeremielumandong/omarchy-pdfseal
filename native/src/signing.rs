use crate::*;
use sha2::{Digest, Sha256};
use std::path::Path;
const KEY: &[u8] = b"PrivSealSigningManifest";

pub fn read(doc: &Document, pages: &[Page]) -> Value {
    doc.catalog()
        .ok()
        .and_then(|d| d.get(KEY).ok())
        .and_then(|o| lopdf::decode_text_string(o).ok())
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .filter(|m| validate(m, pages).is_ok())
        .unwrap_or(Value::Null)
}
fn list<'a>(m: &'a Value, key: &str, max: usize) -> Result<&'a Vec<Value>> {
    m[key]
        .as_array()
        .filter(|a| a.len() <= max)
        .ok_or_else(|| format!("Invalid signing {key}").into())
}
fn label<'a>(m: &'a Value, key: &str) -> Result<&'a str> {
    m[key]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 1000)
        .ok_or_else(|| format!("Invalid signing {key}").into())
}
pub fn validate(m: &Value, pages: &[Page]) -> Result<()> {
    if m["version"] != 1 {
        return Err("Unsupported signing package version".into());
    }
    let recipients = list(m, "recipients", 100)?;
    let fields = list(m, "fields", 300)?;
    let audit = list(m, "audit", 10000)?;
    let mut ids = HashSet::new();
    for r in recipients {
        if !ids.insert(label(r, "id")?) {
            return Err("Duplicate recipient".into());
        }
        label(r, "name")?;
        color(label(r, "color")?)?;
        if r["order"].as_u64().is_none_or(|n| n == 0) {
            return Err("Invalid signing order".into());
        }
    }
    let mut field_ids = HashSet::new();
    for f in fields {
        if !field_ids.insert(label(f, "id")?) || !ids.contains(label(f, "recipientId")?) {
            return Err("Invalid signing field assignment".into());
        }
        let kind = label(f, "type")?;
        if !["signature", "initial", "date", "name", "text", "checkbox"].contains(&kind)
            || f["page"].as_u64().is_none_or(|n| n >= pages.len() as u64)
        {
            return Err("Invalid signing field page or type".into());
        }
        for key in ["xN", "yN", "wN", "hN"] {
            if f[key].as_f64().is_none_or(|n| !(0. ..=1.).contains(&n)) {
                return Err("Invalid signing field bounds".into());
            }
        }
        if f["wN"].as_f64() == Some(0.)
            || f["hN"].as_f64() == Some(0.)
            || f["xN"].as_f64().unwrap() + f["wN"].as_f64().unwrap() > 1.001
            || f["yN"].as_f64().unwrap() + f["hN"].as_f64().unwrap() > 1.001
        {
            return Err("Signing field extends beyond the page".into());
        }
        if f["required"].as_bool().is_none() {
            return Err("Missing signing field requirement".into());
        }
        if !f["value"].is_null() {
            let v = &f["value"];
            match (kind, v["kind"].as_str()) {
                ("signature" | "initial", Some("image")) => {
                    let url = v["dataUrl"]
                        .as_str()
                        .filter(|s| {
                            s.starts_with("data:image/png;base64,") && s.len() < 48 * 1024 * 1024
                        })
                        .ok_or("Invalid signature image")?;
                    if url.len() < 30 {
                        return Err("Empty signature image".into());
                    }
                }
                ("checkbox", Some("check")) if v["checked"].is_boolean() => {}
                ("date" | "name" | "text", Some("text"))
                    if v["text"]
                        .as_str()
                        .is_some_and(|s| !s.trim().is_empty() && s.len() <= 10000) => {}
                _ => return Err("Invalid signing field value".into()),
            }
        }
    }
    for e in audit {
        label(e, "fieldId")?;
        label(e, "recipientId")?;
        label(e, "type")?;
        chrono::DateTime::parse_from_rfc3339(label(e, "at")?)?;
    }
    Ok(())
}
pub fn complete(m: &Value) -> bool {
    m["fields"].as_array().is_some_and(|fields| {
        fields
            .iter()
            .all(|f| f["required"] != true || !f["value"].is_null())
    })
}

pub fn marks(m: &Value, pages: &[Page]) -> Result<Vec<Mark>> {
    validate(m, pages)?;
    let mut marks = vec![];
    for f in m["fields"].as_array().unwrap() {
        let v = &f["value"];
        if v.is_null() {
            continue;
        }
        let page = &pages[f["page"].as_u64().unwrap() as usize];
        let h = f["hN"].as_f64().unwrap() as f32 * page.height;
        let mut mark = json!({"page":page.number,"kind":"text","color":"#211d17","font":"sans","x":f["xN"],"y":f["yN"],"w":f["wN"],"h":f["hN"],"size":(h*0.66).clamp(8.,16.)});
        match v["kind"].as_str().unwrap() {
            "image" => {
                mark["kind"] = json!("image");
                mark["dataUrl"] = v["dataUrl"].clone();
            }
            "check" => {
                if v["checked"] != true {
                    continue;
                }
                mark["text"] = json!("X");
                mark["size"] = json!((h * 0.95).clamp(8., 15.));
            }
            _ => mark["text"] = v["text"].clone(),
        }
        marks.push(serde_json::from_value(mark)?);
    }
    Ok(marks)
}

pub fn remap(m: &Value, pages: &[PageSelection]) -> Value {
    let mut result = m.clone();
    result["fields"] = Value::Array(
        m["fields"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|f| {
                let (index, page) = pages
                    .iter()
                    .enumerate()
                    .find(|(_, p)| p.number == f["page"].as_u64().unwrap() as usize + 1)?;
                let mut f = f.clone();
                f["page"] = json!(index);
                let (x, y, w, h) = (
                    f["xN"].as_f64().unwrap(),
                    f["yN"].as_f64().unwrap(),
                    f["wN"].as_f64().unwrap(),
                    f["hN"].as_f64().unwrap(),
                );
                let rect = match page.rotation {
                    90 => [1. - y - h, x, h, w],
                    180 => [1. - x - w, 1. - y - h, w, h],
                    270 => [y, 1. - x - w, h, w],
                    _ => [x, y, w, h],
                };
                for (key, value) in ["xN", "yN", "wN", "hN"].iter().zip(rect) {
                    f[*key] = json!(value.max(0.));
                }
                Some(f)
            })
            .collect(),
    );
    result
}

pub fn embed(path: &Path, m: &Value) -> Result<()> {
    let bytes = fs::read(path)?;
    let mut m = m.clone();
    m["docHashSha256"] = json!(format!("{:x}", Sha256::digest(&bytes)));
    let mut doc = Document::load_mem(&bytes)?;
    doc.catalog_mut()?
        .set(KEY, text::pdf_string(&m.to_string()));
    doc.save(path)?;
    Ok(())
}

pub fn certificate(path: &Path, m: &Value) -> Result<()> {
    let bytes = fs::read(path)?;
    let hash = format!("{:x}", Sha256::digest(&bytes));
    let mut lines = vec![
        "Certificate of Completion".to_string(),
        format!("Document SHA-256 (before this certificate): {hash}"),
        "Recipients".into(),
    ];
    let mut recipients = m["recipients"].as_array().cloned().unwrap_or_default();
    recipients.sort_by_key(|r| r["order"].as_u64().unwrap_or(0));
    let fields = m["fields"].as_array().cloned().unwrap_or_default();
    for r in &recipients {
        let assigned = fields
            .iter()
            .filter(|f| f["recipientId"] == r["id"])
            .collect::<Vec<_>>();
        lines.push(format!(
            "{}. {} - {}/{} fields completed",
            r["order"],
            r["name"].as_str().unwrap_or(""),
            assigned.iter().filter(|f| !f["value"].is_null()).count(),
            assigned.len()
        ));
    }
    lines.push("Field activity (device clock)".into());
    for event in m["audit"].as_array().into_iter().flatten() {
        let name = recipients
            .iter()
            .find(|r| r["id"] == event["recipientId"])
            .and_then(|r| r["name"].as_str())
            .unwrap_or("Unknown");
        lines.push(format!(
            "{} - {} - {}",
            event["type"].as_str().unwrap_or("Field"),
            name,
            event["at"].as_str().unwrap_or("")
        ));
    }
    lines.push("Signed locally with PDFSeal. Timestamps come from the device clock and are not independently verified. Identities are self-asserted. The digital seal provides tamper evidence; it does not certify identity or provide a qualified timestamp.".into());
    let lines = lines
        .into_iter()
        .flat_map(|s| {
            let chars = s.chars().collect::<Vec<_>>();
            chars
                .chunks(50)
                .map(|s| s.iter().collect::<String>())
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    let mut doc = Document::load_mem(&bytes)?;
    let root = doc.catalog()?.get(b"Pages")?.as_reference()?;
    let mut kids = doc.get_dictionary(root)?.get(b"Kids")?.as_array()?.clone();
    let count = doc.get_pages().len();
    for (index, lines) in lines.chunks(42).enumerate() {
        let id=doc.add_object(dictionary!{"Type"=>"Page","Parent"=>root,"MediaBox"=>vec![0.into(),0.into(),612.into(),792.into()],"Resources"=>dictionary!{}});
        let page = Page {
            number: count + index + 1,
            id,
            width: 612.,
            height: 792.,
            transform: [1., 0., 0., 1., 0., 0.],
        };
        let marks=lines.iter().enumerate().map(|(i,line)|serde_json::from_value::<Mark>(json!({"page":page.number,"kind":"text","color":"#211d17","font":"sans","text":line,"size":if index==0 && i==0 {18}else{10},"x":54./612.,"y":(54.+i as f32*16.+if index==0 && i>0 {12.}else{0.})/792.}))).collect::<std::result::Result<Vec<_>,_>>()?;
        annotate(&mut doc, &page, &marks.iter().collect::<Vec<_>>())?;
        kids.push(id.into());
    }
    let tree = doc.get_object_mut(root)?.as_dict_mut()?;
    tree.set("Kids", kids);
    tree.set("Count", (count + lines.len().div_ceil(42)) as i64);
    doc.save(path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn manifest() -> Value {
        json!({"version":1,"recipients":[{"id":"a","name":"Ada Test","order":1,"color":"#2f5e8c"}],"fields":[{"id":"f","recipientId":"a","type":"name","page":0,"xN":0.1,"yN":0.4,"wN":0.3,"hN":0.07,"required":true,"value":{"kind":"text","text":"Ada Signed"}}],"audit":[{"fieldId":"f","recipientId":"a","type":"name","at":"2026-09-12T12:00:00Z"}],"docHashSha256":""})
    }
    #[test]
    fn package_roundtrip_final_seal_and_audit_are_independently_readable() {
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("input.pdf");
        crate::tests::fixture(&input);
        let session = Session::open(input.to_str().unwrap(), "").unwrap();
        let handoff = dir.path().join("handoff.pdf");
        let request =
            json!({"path":handoff,"pages":[{"number":1}],"marks":[],"signing":manifest()});
        session.export(&request).unwrap();
        let next = Session::open(handoff.to_str().unwrap(), "").unwrap();
        let restored = read(&next.document, &next.pages);
        assert_eq!(restored["fields"], manifest()["fields"]);
        assert_eq!(restored["docHashSha256"].as_str().unwrap().len(), 64);
        let output = dir.path().join("final.pdf");
        let mut request = json!({"path":output,"pages":[{"number":1}],"marks":[],"signing":restored,"seal":{"name":"Ada Test"},"finalize":true,"certificate":true});
        request["signing"]["fields"][0]
            .as_object_mut()
            .unwrap()
            .remove("value");
        assert!(next.export(&request).is_err());
        assert!(!output.exists());
        request["signing"] = restored;
        next.export(&request).unwrap();
        let doc = Document::load(&output).unwrap();
        assert_eq!(doc.get_pages().len(), 2);
        assert!(!doc.catalog().unwrap().has(KEY));
        let text = Command::new("pdftotext")
            .arg(&output)
            .arg("-")
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&text.stdout);
        assert!(text.contains("Ada Signed"));
        assert!(text.contains("Certificate of Completion"), "{text}");
        assert!(text.contains("self-asserted"));
        let signature = Command::new("pdfsig").arg(&output).output().unwrap();
        assert!(String::from_utf8_lossy(&signature.stdout).contains("Signature is Valid"));
        for (rotation, expected) in [
            (90, [0.53, 0.1, 0.07, 0.3]),
            (180, [0.6, 0.53, 0.3, 0.07]),
            (270, [0.4, 0.6, 0.07, 0.3]),
        ] {
            let m = remap(
                &manifest(),
                &[PageSelection {
                    number: 1,
                    rotation,
                }],
            );
            for (key, want) in ["xN", "yN", "wN", "hN"].iter().zip(expected) {
                assert!((m["fields"][0][*key].as_f64().unwrap() - want).abs() < 0.0001);
            }
        }
    }
}
