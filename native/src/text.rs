use crate::*;

pub fn lines(session: &Session, number: usize) -> Result<Value> {
    if number == 0 || number > session.pages.len() {
        return Err("Page out of range".into());
    }
    let cache = session.dir.path().join(format!("text-{number}.json"));
    if cache.exists() {
        return Ok(serde_json::from_slice(&fs::read(cache)?)?);
    }
    let output = jobs::run(
        Command::new("pdftotext")
            .args([
                "-f",
                &number.to_string(),
                "-l",
                &number.to_string(),
                "-cropbox",
                "-raw",
                "-bbox",
            ])
            .arg(&session.snapshot)
            .arg("-"),
        None,
    )?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).to_string().into());
    }
    let xml = String::from_utf8(output.stdout)?;
    let parsed = roxmltree::Document::parse_with_options(
        &xml,
        roxmltree::ParsingOptions {
            allow_dtd: true,
            ..Default::default()
        },
    )?;
    let page = parsed
        .descendants()
        .find(|node| node.has_tag_name("page"))
        .ok_or("Text extraction returned no page")?;
    let value = |node: roxmltree::Node, key: &str| -> Result<f32> {
        Ok(node.attribute(key).ok_or("Missing text bounds")?.parse()?)
    };
    let width = value(page, "width")?;
    let height = value(page, "height")?;
    let mut grouped: Vec<(String, f32, f32, f32, f32, bool)> = vec![];
    for node in page.descendants().filter(|node| node.has_tag_name("word")) {
        let text = node.text().unwrap_or("");
        if text.trim().is_empty() {
            continue;
        }
        let (x, y, right, bottom) = (
            value(node, "xMin")?,
            value(node, "yMin")?,
            value(node, "xMax")?,
            value(node, "yMax")?,
        );
        if let Some(last) = grouped.last_mut()
            && (((y - last.2).abs() < 1.5
                && ((x >= last.3 - 1. && x - last.3 < (bottom - y) * 2.)
                    || (right <= last.1 + 1. && last.1 - right < (bottom - y) * 2.)))
                || (last.5
                    && bottom - y > (right - x) * 1.5
                    && (x - last.1).abs() < 1.5
                    && ((y >= last.4 - 1. && y - last.4 < (right - x) * 2.)
                        || (bottom <= last.2 + 1. && last.2 - bottom < (right - x) * 2.))))
        {
            if (y - last.2).abs() < 1.5 {
                last.5 = false;
            }
            last.0.push(' ');
            last.0.push_str(text);
            last.1 = last.1.min(x);
            last.2 = last.2.min(y);
            last.3 = last.3.max(right);
            last.4 = last.4.max(bottom);
        } else {
            grouped.push((
                text.to_string(),
                x,
                y,
                right,
                bottom,
                bottom - y > (right - x) * 1.5,
            ));
        }
    }
    let lines=grouped.into_iter().map(|(text,x,y,right,bottom,_)|json!({"text":text,"x":(x/width).clamp(0.,1.),"y":(y/height).clamp(0.,1.),
        "w":((right-x)/width).clamp(0.,1.),"h":((bottom-y)/height).clamp(0.,1.),"size":((bottom-y)/0.925).clamp(8.,72.)})).collect::<Vec<_>>();
    let result = json!({"page":number,"lines":lines});
    fs::write(cache, serde_json::to_vec(&result)?)?;
    Ok(result)
}

pub fn search(session: &Session, query: &str) -> Result<Value> {
    if query.trim().is_empty() {
        return Ok(json!({"hits":[]}));
    }
    let query = query.to_lowercase();
    let mut hits = vec![];
    for page in &session.pages {
        jobs::progress(page.number - 1, session.pages.len(), "Searching text")?;
        let result = lines(session, page.number)?;
        for line in result["lines"].as_array().unwrap() {
            if line["text"]
                .as_str()
                .unwrap_or("")
                .to_lowercase()
                .contains(&query)
            {
                let mut hit = line.clone();
                hit["page"] = json!(page.number);
                hits.push(hit);
            }
        }
    }
    Ok(json!({"hits":hits}))
}

pub fn pdf_string(text: &str) -> Object {
    let mut bytes = vec![0xfe, 0xff];
    for code in text.encode_utf16() {
        bytes.extend(code.to_be_bytes());
    }
    Object::string_literal(bytes)
}

pub fn note(doc: &mut Document, page: &Page, mark: &Mark) -> Result<()> {
    let [a, b, c, d, e, f] = page.transform;
    let x = mark.x * page.width;
    let y = (1. - mark.y) * page.height;
    let points = [(x, y), (x + 18., y), (x, y - 18.), (x + 18., y - 18.)]
        .map(|(x, y)| (a * x + c * y + e, b * x + d * y + f));
    let rect = vec![
        points
            .iter()
            .map(|p| p.0)
            .fold(f32::INFINITY, f32::min)
            .into(),
        points
            .iter()
            .map(|p| p.1)
            .fold(f32::INFINITY, f32::min)
            .into(),
        points
            .iter()
            .map(|p| p.0)
            .fold(f32::NEG_INFINITY, f32::max)
            .into(),
        points
            .iter()
            .map(|p| p.1)
            .fold(f32::NEG_INFINITY, f32::max)
            .into(),
    ];
    let note=doc.add_object(dictionary! {"Type"=>"Annot","Subtype"=>"Text","Rect"=>rect,"Contents"=>pdf_string(&mark.text),
        "T"=>pdf_string("PDFSeal"),"Name"=>"Comment","C"=>color(&mark.color)?,"F"=>4,"Open"=>false,"P"=>page.id});
    let mut annots = doc
        .get_dictionary(page.id)?
        .get(b"Annots")
        .ok()
        .and_then(|v| doc.dereference(v).ok())
        .and_then(|(_, v)| v.as_array().ok())
        .cloned()
        .unwrap_or_default();
    annots.push(note.into());
    doc.get_object_mut(page.id)?
        .as_dict_mut()?
        .set("Annots", annots);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn comments_export_as_unicode_pdf_annotations() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.pdf");
        crate::tests::fixture(&source);
        let session = Session::open(source.to_str().unwrap(), "").unwrap();
        let output = dir.path().join("comments.pdf");
        session.export(&json!({"path":output,"pages":[{"number":2},{"number":1}],"marks":[
            {"page":2,"kind":"note","color":"#efcb43","size":1,"x":0.2,"y":0.3,"text":"Review this clause ✓"}]})).unwrap();
        let doc = Document::load(output).unwrap();
        let page = doc.get_pages()[&1];
        let annots = doc.get_dictionary(page).unwrap().get(b"Annots").unwrap();
        let annots = doc.dereference(annots).unwrap().1.as_array().unwrap();
        let note = doc.dereference(&annots[0]).unwrap().1.as_dict().unwrap();
        assert_eq!(note.get(b"Subtype").unwrap().as_name().unwrap(), b"Text");
        assert_eq!(
            lopdf::decode_text_string(note.get(b"Contents").unwrap()).unwrap(),
            "Review this clause ✓"
        );
    }
}
