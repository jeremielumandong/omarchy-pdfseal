use crate::*;
use std::collections::BTreeMap;

#[derive(Clone, Serialize)]
pub struct Field {
    pub id: String,
    pub name: String,
    pub page: usize,
    #[serde(rename = "type")]
    pub kind: String,
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    #[serde(rename = "readOnly")]
    pub read_only: bool,
    pub multiline: bool,
    #[serde(rename = "onValue")]
    pub on_value: String,
    pub options: Vec<Value>,
    pub value: String,
    pub flat: bool,
    #[serde(skip)]
    owner: ObjectId,
    #[serde(skip)]
    widget: ObjectId,
}

impl Field {
    pub fn flat(index: usize, page: usize, kind: &str, rect: [f32; 4]) -> Self {
        Self {
            id: format!("flat#{index}"),
            name: format!("flat#{index}"),
            page,
            kind: kind.into(),
            x: rect[0],
            y: rect[1],
            w: rect[2],
            h: rect[3],
            read_only: false,
            multiline: false,
            on_value: "Yes".into(),
            options: vec![],
            value: String::new(),
            flat: true,
            owner: (0, 0),
            widget: (0, 0),
        }
    }
}

fn string(object: &Object) -> String {
    match object {
        Object::Name(bytes) => String::from_utf8_lossy(bytes).into_owned(),
        _ => lopdf::decode_text_string(object).unwrap_or_default(),
    }
}

fn property(doc: &Document, id: ObjectId, key: &[u8]) -> Option<Object> {
    let mut current = id;
    let mut seen = HashSet::new();
    while seen.insert(current) {
        let dict = doc.get_dictionary(current).ok()?;
        if let Ok(value) = dict.get(key) {
            return doc.dereference(value).ok().map(|(_, v)| v.clone());
        }
        current = dict.get(b"Parent").and_then(Object::as_reference).ok()?;
    }
    None
}

fn field_name(doc: &Document, id: ObjectId) -> Result<(String, ObjectId)> {
    let mut current = id;
    let mut owner = None;
    let mut parts = vec![];
    let mut seen = HashSet::new();
    while seen.insert(current) {
        let dict = doc.get_dictionary(current)?;
        if let Ok(value) = dict.get(b"T") {
            parts.push(string(value));
            owner = owner.or(Some(current));
        }
        let Ok(parent) = dict.get(b"Parent").and_then(Object::as_reference) else {
            break;
        };
        current = parent;
    }
    parts.reverse();
    Ok((parts.join("."), owner.unwrap_or(id)))
}

pub fn normalized_rect(page: &Page, coords: &[f32]) -> Result<[f32; 4]> {
    if coords.len() != 4 || coords.iter().any(|n| !n.is_finite()) {
        return Err("Invalid form field rectangle".into());
    }
    let [a, b, c, d, e, f] = page.transform;
    let det = a * d - b * c;
    let points = [
        (coords[0], coords[1]),
        (coords[2], coords[1]),
        (coords[0], coords[3]),
        (coords[2], coords[3]),
    ]
    .map(|(x, y)| {
        let (x, y) = (x - e, y - f);
        (
            (d * x - c * y) / det / page.width,
            1. - (-b * x + a * y) / det / page.height,
        )
    });
    let x = points
        .iter()
        .map(|p| p.0)
        .fold(f32::INFINITY, f32::min)
        .clamp(0., 1.);
    let y = points
        .iter()
        .map(|p| p.1)
        .fold(f32::INFINITY, f32::min)
        .clamp(0., 1.);
    let right = points
        .iter()
        .map(|p| p.0)
        .fold(f32::NEG_INFINITY, f32::max)
        .clamp(0., 1.);
    let bottom = points
        .iter()
        .map(|p| p.1)
        .fold(f32::NEG_INFINITY, f32::max)
        .clamp(0., 1.);
    Ok([x, y, (right - x).max(0.), (bottom - y).max(0.)])
}

pub fn detect(doc: &Document, pages: &[Page]) -> Result<Vec<Field>> {
    let mut fields = vec![];
    for page in pages {
        let Ok(annots) = doc.get_dictionary(page.id)?.get(b"Annots") else {
            continue;
        };
        let Ok((_, annots)) = doc.dereference(annots) else {
            continue;
        };
        let Ok(annots) = annots.as_array() else {
            continue;
        };
        for object in annots {
            // Unsupported or malformed widgets must not prevent opening the document.
            let parsed = (|| -> Result<Option<Field>> {
                let (id, object) = doc.dereference(object)?;
                let Some(id) = id else {
                    return Ok(None);
                };
                let dict = object.as_dict()?;
                if dict.get(b"Subtype").and_then(Object::as_name).ok() != Some(b"Widget") {
                    return Ok(None);
                }
                let Some(kind) = property(doc, id, b"FT") else {
                    return Ok(None);
                };
                let flags = property(doc, id, b"Ff")
                    .and_then(|o| o.as_i64().ok())
                    .unwrap_or(0);
                let kind = match kind.as_name()? {
                    b"Tx" => "text",
                    b"Ch" => "dropdown",
                    b"Btn" if flags & 65536 == 0 => {
                        if flags & 32768 != 0 {
                            "radio"
                        } else {
                            "checkbox"
                        }
                    }
                    _ => return Ok(None),
                };
                let (name, owner) = field_name(doc, id)?;
                if name.is_empty() {
                    return Ok(None);
                }
                let rect = dict
                    .get(b"Rect")?
                    .as_array()?
                    .iter()
                    .map(Object::as_float)
                    .collect::<lopdf::Result<Vec<_>>>()?;
                let [x, y, w, h] = normalized_rect(page, &rect)?;
                if w == 0. || h == 0. {
                    return Ok(None);
                }
                let appearance = dict
                    .get(b"AP")
                    .ok()
                    .and_then(|o| doc.dereference(o).ok())
                    .and_then(|(_, o)| o.as_dict().ok())
                    .and_then(|d| d.get(b"N").ok())
                    .and_then(|o| doc.dereference(o).ok())
                    .and_then(|(_, o)| o.as_dict().ok());
                let on_value = appearance
                    .and_then(|d| d.iter().find(|(name, _)| name.as_slice() != b"Off"))
                    .map(|(name, _)| String::from_utf8_lossy(name).to_string())
                    .unwrap_or_else(|| "Yes".into());
                let value = property(doc, id, b"V")
                    .map(|o| string(&o))
                    .unwrap_or_default();
                let options=property(doc,id,b"Opt").and_then(|o|o.as_array().ok().cloned()).unwrap_or_default().iter().map(|o|{
                if let Ok(pair)=o.as_array() {json!({"value":pair.first().map(string).unwrap_or_default(),"label":pair.get(1).or(pair.first()).map(string).unwrap_or_default()})}
                else {let text=string(o);json!({"value":text,"label":text})}
            }).collect();
                Ok(Some(Field {
                    id: format!("{}-{}", id.0, id.1),
                    name,
                    page: page.number,
                    kind: kind.into(),
                    x,
                    y,
                    w,
                    h,
                    read_only: flags & 1 != 0,
                    multiline: flags & 4096 != 0,
                    on_value,
                    options,
                    value: if value == "Off" { String::new() } else { value },
                    owner,
                    widget: id,
                    flat: false,
                }))
            })();
            if let Ok(Some(field)) = parsed {
                fields.push(field);
            }
        }
    }
    Ok(fields)
}

pub fn metadata(doc: &Document, pages: &[Page]) -> Result<Value> {
    let mut fields = detect(doc, pages)?;
    if fields.is_empty() {
        fields = flat_forms::detect(doc, pages)?;
    }
    let values = fields
        .iter()
        .map(|f| (f.name.clone(), f.value.clone()))
        .collect::<BTreeMap<_, _>>();
    Ok(json!({"fields":fields,"values":values}))
}

fn appearance(doc: &mut Document, field: &Field, value: &str) -> Result<ObjectId> {
    let rect = doc.get_dictionary(field.widget)?.get(b"Rect")?.as_array()?;
    let w = (rect[2].as_float()? - rect[0].as_float()?).abs();
    let h = (rect[3].as_float()? - rect[1].as_float()?).abs();
    let (encoded, _, bad) = WINDOWS_1252.encode(value);
    if bad {
        return Err(format!(
            "The appearance for form field {} supports Western European characters",
            field.name
        )
        .into());
    }
    let size = (h * 0.6)
        .min((h - 4.).max(1.) / (value.lines().count().max(1) as f32 * 1.2))
        .min(18.)
        .min(
            (w - 4.).max(1.) / (value.lines().map(str::len).max().unwrap_or(1).max(1) as f32 * 0.6),
        )
        .max(4.);
    let font=doc.add_object(dictionary!{"Type"=>"Font","Subtype"=>"Type1","BaseFont"=>"Helvetica","Encoding"=>"WinAnsiEncoding"});
    let mut operations = vec![
        Operation::new("BMC", vec!["Tx".into()]),
        op("q", &[]),
        op("re", &[0., 0., w, h]),
        op("W", &[]),
        op("n", &[]),
        op("g", &[1.]),
        op("re", &[0., 0., w, h]),
        op("f", &[]),
    ];
    operations.extend([
        op("g", &[0.]),
        op("BT", &[]),
        Operation::new("Tf", vec!["F".into(), size.into()]),
        op("Td", &[2., h - size - 2.]),
    ]);
    for (index, line) in encoded.split(|b| *b == b'\n').enumerate() {
        if index > 0 {
            operations.push(op("Td", &[0., -size * 1.2]));
        }
        operations.push(Operation::new("Tj", vec![Object::string_literal(line)]));
    }
    operations.extend([op("ET", &[]), op("Q", &[]), op("EMC", &[])]);
    Ok(doc.add_object(Stream::new(dictionary!{"Type"=>"XObject","Subtype"=>"Form","BBox"=>vec![0.into(),0.into(),w.into(),h.into()],
        "Resources"=>dictionary!{"Font"=>dictionary!{"F"=>font}}},Content{operations}.encode()?)))
}

pub fn fill(doc: &mut Document, pages: &[Page], values: &Value) -> Result<()> {
    let fields = detect(doc, pages)?;
    if fields.is_empty()
        && values.as_object().is_some_and(|v| {
            v.values()
                .any(|v| v.as_str().is_some_and(|s| !s.is_empty()))
        })
    {
        let fields = flat_forms::detect(doc, pages)?;
        return flat_forms::fill(doc, pages, &fields, values);
    }
    let Some(values) = values.as_object() else {
        return Ok(());
    };
    for field in fields {
        let Some(value) = values.get(&field.name).and_then(Value::as_str) else {
            continue;
        };
        if value == field.value {
            continue;
        }
        if field.read_only {
            return Err(format!("Form field {} is read-only", field.name).into());
        }
        if field.kind == "text" || field.kind == "dropdown" {
            if field.kind == "dropdown"
                && !value.is_empty()
                && !field.options.iter().any(|o| o["value"] == value)
            {
                return Err("Choose a listed form option".into());
            }
            let shown = if field.kind == "dropdown" {
                field
                    .options
                    .iter()
                    .find(|o| o["value"] == value)
                    .and_then(|o| o["label"].as_str())
                    .unwrap_or(value)
            } else {
                value
            };
            let appearance = appearance(doc, &field, shown)?;
            doc.get_object_mut(field.owner)?
                .as_dict_mut()?
                .set("V", text::pdf_string(value));
            doc.get_object_mut(field.widget)?
                .as_dict_mut()?
                .set("AP", dictionary! {"N"=>appearance});
        } else {
            let state = if value == field.on_value {
                field.on_value.as_str()
            } else {
                "Off"
            };
            doc.get_object_mut(field.widget)?
                .as_dict_mut()?
                .set("AS", Object::Name(state.as_bytes().to_vec()));
            doc.get_object_mut(field.owner)?.as_dict_mut()?.set(
                "V",
                Object::Name(if value.is_empty() {
                    b"Off".to_vec()
                } else {
                    value.as_bytes().to_vec()
                }),
            );
        }
    }

    Ok(())
}

pub fn prepare_flatten(doc: &mut Document, pages: &[Page]) -> Result<()> {
    for field in detect(doc, pages)? {
        if field.kind == "text" || field.kind == "dropdown" {
            let has_appearance = doc
                .get_dictionary(field.widget)?
                .get(b"AP")
                .ok()
                .and_then(|o| doc.dereference(o).ok())
                .and_then(|(_, o)| o.as_dict().ok())
                .is_some_and(|d| d.has(b"N"));
            if !has_appearance {
                let shown = field
                    .options
                    .iter()
                    .find(|o| o["value"] == field.value)
                    .and_then(|o| o["label"].as_str())
                    .unwrap_or(&field.value);
                let appearance = appearance(doc, &field, shown)?;
                doc.get_object_mut(field.widget)?
                    .as_dict_mut()?
                    .set("AP", dictionary! {"N"=>appearance});
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fills_form_widgets_and_groups_then_flattens() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("form.pdf");
        assert!(
            Command::new("python3")
                .arg(
                    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                        .join("../tests/make-form-fixture.py")
                )
                .arg(&source)
                .status()
                .unwrap()
                .success()
        );
        let session = Session::open(source.to_str().unwrap(), "").unwrap();
        assert_eq!(detect(&session.document, &session.pages).unwrap().len(), 6);
        let output = dir.path().join("filled.pdf");
        let mut request = json!({"path":output,"pages":[{"number":1}],"marks":[],"formValues":{"FullName":"Grace Hopper","Agree":"","Choice":"Two","Select":"Beta","Locked":"Fixed"}});
        session.export(&request).unwrap();
        let mut next = Session::open(output.to_str().unwrap(), "").unwrap();
        let fields = detect(&next.document, &next.pages).unwrap();
        for (name, value) in [
            ("FullName", "Grace Hopper"),
            ("Agree", ""),
            ("Choice", "Two"),
            ("Select", "Beta"),
        ] {
            assert!(
                fields
                    .iter()
                    .filter(|f| f.name == name)
                    .all(|f| f.value == value)
            );
        }
        for field in fields.iter().filter(|f| f.kind == "radio") {
            let state = next
                .document
                .get_dictionary(field.widget)
                .unwrap()
                .get(b"AS")
                .unwrap()
                .as_name()
                .unwrap();
            assert_eq!(
                state,
                if field.on_value == "Two" {
                    b"Two"
                } else {
                    b"Off"
                }
            );
        }
        request["formValues"]["Locked"] = json!("Changed");
        assert!(session.export(&request).is_err());
        operations::apply(
            &mut next,
            &json!({"action":"flatten","pages":[{"number":1}],"marks":[]}),
        )
        .unwrap();
        assert!(detect(&next.document, &next.pages).unwrap().is_empty());
        let text = Command::new("pdftotext")
            .arg(&next.snapshot)
            .arg("-")
            .output()
            .unwrap();
        assert!(
            String::from_utf8_lossy(&text.stdout).contains("Grace Hopper"),
            "{}",
            String::from_utf8_lossy(&text.stdout)
        );
        assert!(String::from_utf8_lossy(&text.stdout).contains("Beta"));
        assert!(String::from_utf8_lossy(&text.stdout).contains("Fixed"));
    }
}
