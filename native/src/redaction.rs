use crate::*;
use std::path::Path;

pub struct Audit {
    pub pages: HashSet<usize>,
    pub covered: Vec<String>,
}

pub fn rebuild(
    doc: &mut Document,
    session: &Session,
    annotated: &Path,
    marks: &[Mark],
) -> Result<Audit> {
    let affected = marks
        .iter()
        .filter(|m| m.kind == "redact")
        .map(|m| m.page)
        .collect::<HashSet<_>>();
    let baked = Session::open(annotated.to_str().ok_or("Invalid working path")?, "")?;
    let mut covered = vec![];
    for (index, number) in affected.iter().enumerate() {
        jobs::progress(index, affected.len(), "Removing redacted content")?;
        let extracted = text::lines(&baked, *number)?;
        for line in extracted["lines"].as_array().unwrap() {
            let val = |key: &str| line[key].as_f64().unwrap_or(0.) as f32;
            if marks
                .iter()
                .filter(|m| m.page == *number && m.kind == "redact")
                .any(|m| {
                    val("x") < m.x + m.w
                        && val("x") + val("w") > m.x
                        && val("y") < m.y + m.h
                        && val("y") + val("h") > m.y
                })
            {
                covered.push(line["text"].as_str().unwrap_or("").to_string());
            }
        }
        let page = &session.pages[number - 1];
        let image = operations::raster(
            annotated,
            *number,
            &baked.dir.path().join(format!("redact-{number}")),
            300,
            false,
        )?;
        let parent = doc
            .get_dictionary(page.id)?
            .get(b"Parent")?
            .as_reference()?;
        let replacement =
            operations::image_page(doc, parent, &image, page.width, page.height, false)?;
        let dictionary = doc
            .objects
            .remove(&replacement)
            .ok_or("Missing raster page")?;
        doc.objects.insert(page.id, dictionary);
    }
    Ok(Audit {
        pages: affected,
        covered,
    })
}

pub fn verify(path: &Path, pages: &[PageSelection], audit: &Audit) -> Result<()> {
    jobs::progress(1, 1, "Verifying redaction")?;
    let result = Session::open(path.to_str().ok_or("Invalid export path")?, "")?;
    let mut all_text = String::new();
    for (index, selected) in pages.iter().enumerate() {
        let extracted = text::lines(&result, index + 1)?;
        let lines = extracted["lines"].as_array().unwrap();
        if audit.pages.contains(&selected.number) && !lines.is_empty() {
            return Err("Redaction verification failed: text remains on a redacted page".into());
        }
        for line in lines {
            all_text.push_str(line["text"].as_str().unwrap_or(""));
            all_text.push('\n');
        }
    }
    let bytes = fs::read(path)?;
    for text in audit
        .covered
        .iter()
        .map(|s| s.trim())
        .filter(|s| s.chars().count() >= 3)
    {
        let latin = WINDOWS_1252.encode(text).0;
        let utf16 = text
            .encode_utf16()
            .flat_map(u16::to_be_bytes)
            .collect::<Vec<_>>();
        if all_text
            .split_whitespace()
            .collect::<String>()
            .contains(&text.split_whitespace().collect::<String>())
            || bytes.windows(latin.len()).any(|w| w == latin.as_ref())
            || bytes.windows(utf16.len()).any(|w| w == utf16)
        {
            return Err("Redaction verification failed: covered text still occurs in the document. Redact every occurrence before exporting.".into());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn redaction_removes_text_and_comments_and_verifies_all_occurrences() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.pdf");
        crate::tests::fixture(&source);
        let session = Session::open(source.to_str().unwrap(), "").unwrap();
        let original = fs::read(&source).unwrap();
        let lines = text::lines(&session, 1).unwrap();
        let line = &lines["lines"][0];
        let mut marks = vec![];
        for number in 1..=2 {
            marks.push(json!({"page":number,"kind":"redact","color":"#000000","size":1,"x":0,"y":0,"w":1,"h":1}));
        }
        assert!(line["text"].as_str().unwrap().contains("Original content"));
        let output = dir.path().join("redacted.pdf");
        let mut request =
            json!({"path":output,"pages":[{"number":2,"rotation":90},{"number":1}],"marks":marks});
        session.export(&request).unwrap();
        let text = Command::new("pdftotext")
            .arg(&output)
            .arg("-")
            .output()
            .unwrap();
        assert!(String::from_utf8_lossy(&text.stdout).trim().is_empty());
        let doc = Document::load(&output).unwrap();
        for id in doc.get_pages().values() {
            assert!(!doc.get_dictionary(*id).unwrap().has(b"Annots"));
        }
        assert!(
            !fs::read(&output)
                .unwrap()
                .windows(16)
                .any(|w| w == b"Original content")
        );
        let protected = fs::read(&output).unwrap();
        request["marks"].as_array_mut().unwrap().pop();
        assert!(
            session
                .export(&request)
                .unwrap_err()
                .to_string()
                .contains("verification failed")
        );
        assert_eq!(fs::read(&output).unwrap(), protected);
        assert_eq!(fs::read(&source).unwrap(), original);
    }
}
