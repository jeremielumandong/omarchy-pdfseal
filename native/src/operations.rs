use crate::*;
use std::path::Path;

fn checked_output(command: &mut Command) -> Result<Vec<u8>> {
    let output = jobs::run(command, None)?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr)
            .trim()
            .to_string()
            .into());
    }
    Ok(output.stdout)
}

pub fn raster(path: &Path, number: usize, prefix: &Path, dpi: u32, jpeg: bool) -> Result<PathBuf> {
    checked_output(
        Command::new("pdftoppm")
            .args([
                "-f",
                &number.to_string(),
                "-l",
                &number.to_string(),
                "-r",
                &dpi.to_string(),
                "-cropbox",
                "-singlefile",
                if jpeg { "-jpeg" } else { "-png" },
            ])
            .arg(path)
            .arg(prefix),
    )?;
    Ok(prefix.with_extension(if jpeg { "jpg" } else { "png" }))
}

pub fn image_page(
    doc: &mut Document,
    parent: ObjectId,
    source: &Path,
    width: f32,
    height: f32,
    jpeg: bool,
) -> Result<ObjectId> {
    let image = if jpeg {
        let (w, h) = image::image_dimensions(source)?;
        doc.add_object(Stream::new(
            dictionary! {"Type"=>"XObject","Subtype"=>"Image","Width"=>w,"Height"=>h,
            "ColorSpace"=>"DeviceRGB","BitsPerComponent"=>8,"Filter"=>"DCTDecode"},
            fs::read(source)?,
        ))
    } else {
        images::embed(doc, source.to_str().ok_or("Invalid image path")?)?
    };
    let content = doc.add_object(Stream::new(
        dictionary! {},
        Content {
            operations: vec![
                op("q", &[]),
                op("cm", &[width, 0., 0., height, 0., 0.]),
                Operation::new("Do", vec!["Image".into()]),
                op("Q", &[]),
            ],
        }
        .encode()?,
    ));
    Ok(doc.add_object(dictionary! {"Type"=>"Page", "Parent"=>parent, "MediaBox"=>vec![0.into(),0.into(),width.into(),height.into()],
        "Resources"=>dictionary!{"XObject"=>dictionary!{"Image"=>image}}, "Contents"=>content }))
}

fn finish_pages(
    doc: &mut Document,
    parent: ObjectId,
    pages: Vec<ObjectId>,
    path: &Path,
) -> Result<()> {
    doc.objects.insert(
        parent,
        dictionary! {"Type"=>"Pages", "Count"=>pages.len() as i64,
        "Kids"=>pages.into_iter().map(Object::Reference).collect::<Vec<_>>()}
        .into(),
    );
    let catalog = doc.add_object(dictionary! {"Type"=>"Catalog", "Pages"=>parent});
    doc.trailer.set("Root", catalog);
    doc.save(path)?;
    Ok(())
}

fn compact(input: &Path, output: &Path, work: &Path, pages: &[Page]) -> Result<()> {
    let mut doc = Document::with_version("1.7");
    let parent = doc.new_object_id();
    let mut ids = vec![];
    for (index, page) in pages.iter().enumerate() {
        jobs::progress(index, pages.len(), "Compressing pages")?;
        let image = raster(
            input,
            page.number,
            &work.join(format!("compact-{}", page.number)),
            120,
            true,
        )?;
        ids.push(image_page(
            &mut doc,
            parent,
            &image,
            page.width,
            page.height,
            true,
        )?);
        fs::remove_file(image)?;
    }
    finish_pages(&mut doc, parent, ids, output)
}

pub fn images_pdf(paths: &[Value], output: &Path) -> Result<()> {
    if paths.is_empty() {
        return Err("Choose at least one image".into());
    }
    let mut doc = Document::with_version("1.7");
    let parent = doc.new_object_id();
    let mut ids = vec![];
    for (index, value) in paths.iter().enumerate() {
        jobs::progress(index, paths.len(), "Converting images")?;
        let path = Path::new(value.as_str().ok_or("Invalid image path")?);
        // Decode through our bounded image reader before using image dimensions.
        let pixels = images::decode(path.to_str().ok_or("Invalid image path")?)?;
        ids.push(image_page(
            &mut doc,
            parent,
            path,
            pixels.width() as f32,
            pixels.height() as f32,
            false,
        )?);
    }
    finish_pages(&mut doc, parent, ids, output)
}

fn crop(doc: &mut Document, pages: &[Page], request: &Value) -> Result<()> {
    let side = |key: &str| -> Result<f32> {
        let value = request[key].as_f64().unwrap_or(0.) as f32;
        if !(0. ..=0.49).contains(&value) {
            return Err("Crop margins must be between 0 and 49 percent".into());
        }
        Ok(value)
    };
    let (left, top, right, bottom) = (side("left")?, side("top")?, side("right")?, side("bottom")?);
    for page in pages {
        if request["only"]
            .as_u64()
            .is_some_and(|number| number != page.number as u64)
        {
            continue;
        }
        let [a, b, c, d, e, f] = page.transform;
        let corners = [
            (left, bottom),
            (1. - right, bottom),
            (left, 1. - top),
            (1. - right, 1. - top),
        ]
        .map(|(x, y)| {
            let (x, y) = (x * page.width, y * page.height);
            (a * x + c * y + e, b * x + d * y + f)
        });
        let xmin = corners.iter().map(|p| p.0).fold(f32::INFINITY, f32::min);
        let ymin = corners.iter().map(|p| p.1).fold(f32::INFINITY, f32::min);
        let xmax = corners
            .iter()
            .map(|p| p.0)
            .fold(f32::NEG_INFINITY, f32::max);
        let ymax = corners
            .iter()
            .map(|p| p.1)
            .fold(f32::NEG_INFINITY, f32::max);
        doc.get_object_mut(page.id)?.as_dict_mut()?.set(
            "CropBox",
            vec![xmin.into(), ymin.into(), xmax.into(), ymax.into()],
        );
    }
    Ok(())
}

fn lettering(doc: &mut Document, pages: &[Page], request: &Value, numbers: bool) -> Result<()> {
    let size = request["size"]
        .as_f64()
        .unwrap_or(if numbers { 12. } else { 60. }) as f32;
    let opacity = request["opacity"]
        .as_f64()
        .unwrap_or(if numbers { 1. } else { 0.25 });
    if !(6. ..=200.).contains(&size) || !(0. ..=1.).contains(&opacity) {
        return Err("Invalid font size or opacity".into());
    }
    let rotation = if numbers {
        0.
    } else {
        request["rotation"].as_f64().unwrap_or(45.) as f32
    };
    for (index, page) in pages.iter().enumerate() {
        let text = if numbers {
            (request["start"].as_i64().unwrap_or(1) + index as i64).to_string()
        } else {
            required_str(request, "text")?.to_string()
        };
        if text.is_empty() {
            return Err("Enter watermark text".into());
        }
        let width = text.chars().count() as f32 * size * if numbers { 0.556 } else { 0.65 };
        let (x, y) = if numbers {
            let position = request["position"].as_str().unwrap_or("bottom-center");
            let x = if position.ends_with("left") {
                24.
            } else if position.ends_with("right") {
                page.width - 24. - width
            } else {
                (page.width - width) / 2.
            };
            (
                x / page.width,
                if position.starts_with("top") {
                    24. / page.height
                } else {
                    1. - (24. + size) / page.height
                },
            )
        } else {
            (0.5, 0.5)
        };
        let mark: Mark = serde_json::from_value(
            json!({"kind":"text","page":page.number,"color":"#808080",
            "font":if numbers {"sans"} else {"bold"},"text":text,"size":size,"x":x.max(0.),"y":y.max(0.),
            "opacity":opacity,"angle":rotation,"centered":!numbers}),
        )?;
        annotate(doc, page, &[&mark])?;
    }
    Ok(())
}

fn ocr(input: &Path, output: &Path, work: &Path, pages: &[Page]) -> Result<()> {
    let mut overlays = vec![];
    for (index, page) in pages.iter().enumerate() {
        jobs::progress(index, pages.len(), "Recognizing text (English)")?;
        let prefix = work.join(format!("ocr-{}", page.number));
        let image = raster(input, page.number, &prefix, 216, false)?;
        checked_output(Command::new("tesseract").arg(&image).arg(&prefix).args([
            "-l",
            "eng",
            "--dpi",
            "216",
            "-c",
            "textonly_pdf=1",
            "pdf",
        ]))?;
        overlays.push(
            json!({"file":prefix.with_extension("pdf"),"to":page.number.to_string(),"from":"1"}),
        );
        fs::remove_file(image)?;
    }
    qpdf(json!({"inputFile":input,"outputFile":output,"overlay":overlays}))
}

pub fn apply(session: &mut Session, request: &Value) -> Result<Value> {
    let work = tempfile::Builder::new()
        .prefix("operation-")
        .tempdir_in(session.dir.path())?;
    let input = work.path().join("input.pdf");
    let output = work.path().join("output.pdf");
    let mut bake = request.clone();
    bake["path"] = json!(input);
    bake["password"] = json!("");
    bake["compress"] = json!(false);
    jobs::progress(0, 1, "Preparing document")?;
    session.export(&bake)?;
    let mut doc = Document::load(&input)?;
    let pages = doc
        .get_pages()
        .into_iter()
        .map(|(n, id)| geometry(&doc, n as usize, id))
        .collect::<Result<Vec<_>>>()?;
    let action = required_str(request, "action")?;
    match action {
        "redact" => {
            fs::copy(&input, &output)?;
        }
        "crop" => {
            crop(&mut doc, &pages, request)?;
            doc.save(&output)?;
        }
        "watermark" | "numbers" => {
            lettering(&mut doc, &pages, request, action == "numbers")?;
            doc.save(&output)?;
        }
        "duplicate" => {
            let number = request["number"].as_u64().ok_or("Choose a page")? as usize;
            if number == 0 || number > pages.len() {
                return Err("Page out of range".into());
            }
            let mut range = vec![];
            for page in &pages {
                range.push(page.number.to_string());
                if page.number == number {
                    range.push(page.number.to_string());
                }
            }
            qpdf(
                json!({"inputFile":input,"outputFile":output,"pages":[{"file":".","range":range.join(",")}]}),
            )?;
        }
        "merge" | "images" => {
            let added = if action == "images" {
                let path = work.path().join("images.pdf");
                images_pdf(request["paths"].as_array().ok_or("Choose images")?, &path)?;
                path
            } else {
                PathBuf::from(required_str(request, "file")?)
            };
            qpdf(
                json!({"inputFile":input,"outputFile":output,"pages":[{"file":".","range":"1-z"},
                {"file":added,"range":"1-z","password":request["filePassword"].as_str().unwrap_or("")}]}),
            )?;
        }
        "extract" => {
            let numbers = selection(request, pages.len())?;
            qpdf(
                json!({"inputFile":input,"outputFile":output,"pages":[{"file":".","range":numbers.iter().map(usize::to_string).collect::<Vec<_>>().join(",")}]}),
            )?;
        }
        "flatten" => {
            forms::prepare_flatten(&mut doc, &pages)?;
            doc.save(&input)?;
            qpdf(
                json!({"inputFile":input,"outputFile":output,"generateAppearances":"","flattenAnnotations":"all","removeAcroform":""}),
            )?;
        }
        "compress" => {
            match request["preset"].as_str().unwrap_or("lossless") {
                "compact" => compact(&input, &output, work.path(), &pages)?,
                "lossless" | "images" => {
                    let mut job = json!({"inputFile":input,"outputFile":output,"objectStreams":"generate","compressStreams":"y","recompressFlate":"","compressionLevel":"9"});
                    if request["preset"] == "images" {
                        job["optimizeImages"] = json!("");
                        job["jpegQuality"] = json!("72");
                    }
                    qpdf(job)?;
                }
                _ => return Err("Unknown compression preset".into()),
            }
            // Preview is isolated from the open document until the user chooses Replace.
            let candidate = session.dir.path().join("compression-preview.pdf");
            fs::copy(&output, &candidate)?;
            return Ok(
                json!({"candidate":true,"before":fs::metadata(&input)?.len(),"after":fs::metadata(&output)?.len()}),
            );
        }
        "ocr" => ocr(&input, &output, work.path(), &pages)?,
        "split" | "png" | "jpeg" => {
            let folder = PathBuf::from(required_str(request, "folder")?);
            let staged = tempfile::Builder::new()
                .prefix("pdfseal-export-")
                .tempdir_in(&folder)?;
            for (index, page) in pages.iter().enumerate() {
                jobs::progress(
                    index,
                    pages.len(),
                    if action == "split" {
                        "Splitting pages"
                    } else {
                        "Exporting images"
                    },
                )?;
                let prefix = staged.path().join(format!("page-{:03}", page.number));
                if action == "split" {
                    qpdf(
                        json!({"inputFile":input,"outputFile":prefix.with_extension("pdf"),"pages":[{"file":".","range":page.number.to_string()}]}),
                    )?;
                } else {
                    raster(&input, page.number, &prefix, 144, action == "jpeg")?;
                }
            }
            jobs::check()?;
            let path = staged.keep();
            return Ok(json!({"folder":path,"count":pages.len()}));
        }
        _ => return Err("Unknown document tool".into()),
    }
    adopt(session, &output)
}

pub fn adopt(session: &mut Session, path: &Path) -> Result<Value> {
    let mut next = Session::open(path.to_str().ok_or("Invalid PDF path")?, "")?;
    next.source = session.source.clone();
    jobs::check()?;
    let result = json!({"pages":next.pages,"path":next.source,"baked":true,"forms":forms::metadata(&next.document,&next.pages)?});
    *session = next;
    Ok(result)
}

fn selection(request: &Value, count: usize) -> Result<Vec<usize>> {
    let text = required_str(request, "selection")?;
    let mut numbers = vec![];
    for part in text.split(',') {
        let part = part.trim();
        if let Some((start, end)) = part.split_once('-') {
            let (start, end) = (start.trim().parse::<usize>()?, end.trim().parse::<usize>()?);
            if start > end || end > count || start == 0 {
                return Err("Invalid page range".into());
            }
            numbers.extend(start..=end);
        } else {
            numbers.push(part.parse::<usize>()?);
        }
    }
    if numbers.is_empty() || numbers.iter().any(|n| *n == 0 || *n > count) {
        return Err("Choose pages within the document".into());
    }
    Ok(numbers)
}

pub fn accept_compression(session: &mut Session, request: &Value) -> Result<Value> {
    let candidate = session.dir.path().join("compression-preview.pdf");
    if let Some(path) = request["path"].as_str() {
        let destination = Path::new(path);
        if fs::canonicalize(destination).ok().as_ref() == Some(&session.source) {
            return Err("Choose a new filename".into());
        }
        let mut temp = NamedTempFile::new_in(destination.parent().ok_or("Invalid destination")?)?;
        std::io::copy(&mut fs::File::open(&candidate)?, &mut temp)?;
        temp.as_file().sync_all()?;
        jobs::check()?;
        temp.persist(destination).map_err(|e| e.error)?;
        Ok(json!({"saved":path}))
    } else {
        adopt(session, &candidate)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn request(session: &Session, action: &str, options: Value) -> Value {
        let mut request = options;
        request["action"] = json!(action);
        request["marks"] = json!([]);
        request["pages"] = json!(
            session
                .pages
                .iter()
                .map(|p| json!({"number":p.number}))
                .collect::<Vec<_>>()
        );
        request
    }
    #[test]
    fn document_operations_preserve_original_and_commit_only_on_success() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.pdf");
        crate::tests::fixture(&source);
        let original = fs::read(&source).unwrap();
        let mut session = Session::open(source.to_str().unwrap(), "").unwrap();
        let req = request(
            &session,
            "crop",
            json!({"left":0.1,"right":0.2,"top":0.1,"bottom":0.1}),
        );
        assert_eq!(apply(&mut session, &req).unwrap()["baked"], true);
        assert!((session.pages[0].width - 280.).abs() < 0.01);
        assert!((session.pages[1].width - 490.).abs() < 0.01);
        let prior = fs::read(&session.snapshot).unwrap();
        let req = request(&session, "extract", json!({"selection":"999"}));
        assert!(apply(&mut session, &req).is_err());
        assert_eq!(fs::read(&session.snapshot).unwrap(), prior);
        let req = request(&session, "duplicate", json!({"number":1}));
        apply(&mut session, &req).unwrap();
        assert_eq!(session.pages.len(), 3);
        let req = request(
            &session,
            "numbers",
            json!({"start":7,"position":"top-right"}),
        );
        apply(&mut session, &req).unwrap();
        let text =
            checked_output(Command::new("pdftotext").arg(&session.snapshot).arg("-")).unwrap();
        assert!(String::from_utf8_lossy(&text).contains('7'));
        assert!(String::from_utf8_lossy(&text).contains('9'));
        let req = request(&session, "watermark", json!({"text":"CONFIDENTIAL"}));
        apply(&mut session, &req).unwrap();
        let text =
            checked_output(Command::new("pdftotext").arg(&session.snapshot).arg("-")).unwrap();
        assert!(
            String::from_utf8_lossy(&text)
                .replace(char::is_whitespace, "")
                .contains("CONFIDENTIAL")
        );
        let req = request(&session, "split", json!({"folder":dir.path()}));
        let result = apply(&mut session, &req).unwrap();
        assert_eq!(
            fs::read_dir(result["folder"].as_str().unwrap())
                .unwrap()
                .count(),
            3
        );
        let req = request(&session, "extract", json!({"selection":"3,1"}));
        apply(&mut session, &req).unwrap();
        assert_eq!(session.pages.len(), 2);
        let req = request(&session, "merge", json!({"file":source}));
        apply(&mut session, &req).unwrap();
        assert_eq!(session.pages.len(), 4);
        let prior = fs::read(&session.snapshot).unwrap();
        let req = request(&session, "compress", json!({"preset":"images"}));
        assert_eq!(apply(&mut session, &req).unwrap()["candidate"], true);
        assert_eq!(fs::read(&session.snapshot).unwrap(), prior);
        accept_compression(&mut session, &json!({})).unwrap();
        assert_eq!(session.pages.len(), 4);
        assert_eq!(fs::read(&source).unwrap(), original);
    }

    #[test]
    fn image_conversion_compact_and_ocr_are_independently_readable() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.pdf");
        crate::tests::fixture(&source);
        let mut session = Session::open(source.to_str().unwrap(), "").unwrap();
        let req = request(&session, "png", json!({"folder":dir.path()}));
        let result = apply(&mut session, &req).unwrap();
        let image = PathBuf::from(result["folder"].as_str().unwrap()).join("page-001.png");
        let output = dir.path().join("image.pdf");
        images_pdf(&[json!(image)], &output).unwrap();
        let mut image_session = Session::open(output.to_str().unwrap(), "").unwrap();
        assert_eq!(image_session.pages[0].width, 800.);
        let req = request(&image_session, "ocr", json!({}));
        apply(&mut image_session, &req).unwrap();
        let text = checked_output(
            Command::new("pdftotext")
                .arg(&image_session.snapshot)
                .arg("-"),
        )
        .unwrap();
        assert!(
            String::from_utf8_lossy(&text).contains("Original content"),
            "{}",
            String::from_utf8_lossy(&text)
        );
        let req = request(&session, "compress", json!({"preset":"compact"}));
        apply(&mut session, &req).unwrap();
        accept_compression(&mut session, &json!({})).unwrap();
        let text =
            checked_output(Command::new("pdftotext").arg(&session.snapshot).arg("-")).unwrap();
        assert!(String::from_utf8_lossy(&text).trim().is_empty());
        assert_eq!(session.pages[1].width, 700.);
    }
}
