use encoding_rs::WINDOWS_1252;
use lopdf::content::{Content, Operation};
use lopdf::{Document, Object, ObjectId, Stream, dictionary};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{HashSet, VecDeque};
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tempfile::{NamedTempFile, TempDir};

#[derive(Debug)]
struct PasswordRequired;
impl std::fmt::Display for PasswordRequired {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("This PDF requires a valid password")
    }
}
impl std::error::Error for PasswordRequired {}

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
mod images;

#[derive(Clone, Serialize)]
struct Page {
    number: usize,
    width: f32,
    height: f32,
    #[serde(skip)]
    id: ObjectId,
    #[serde(skip)]
    transform: [f32; 6],
}

#[derive(Deserialize)]
struct PageSelection {
    number: usize,
    #[serde(default)]
    rotation: u16,
}

#[derive(Clone, Deserialize)]
struct Mark {
    page: usize,
    kind: String,
    color: String,
    #[serde(default = "default_size")]
    size: f32,
    #[serde(default)]
    x: f32,
    #[serde(default)]
    y: f32,
    #[serde(default)]
    w: f32,
    #[serde(default)]
    h: f32,
    #[serde(default)]
    text: String,
    #[serde(default)]
    font: String,
    #[serde(default, rename = "dataUrl")]
    image_data: String,
    #[serde(default)]
    points: Vec<[f32; 2]>,
}

fn default_size() -> f32 {
    2.0
}

struct Session {
    dir: TempDir,
    source: PathBuf,
    snapshot: PathBuf,
    document: Document,
    pages: Vec<Page>,
    previews: VecDeque<PathBuf>,
}

/// Arguments and passwords travel on stdin, never through a shell or process argv.
fn qpdf(job: Value) -> Result<()> {
    let mut child = Command::new("qpdf")
        .arg("--job-json-file=/dev/stdin")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Could not start qpdf: {e}. Install the qpdf package."))?;
    let write_result = child
        .stdin
        .take()
        .unwrap()
        .write_all(job.to_string().as_bytes());
    let output = child.wait_with_output()?;
    write_result?;
    if !output.status.success() && output.status.code() != Some(3) {
        if String::from_utf8_lossy(&output.stderr)
            .to_lowercase()
            .contains("invalid password")
        {
            return Err(Box::new(PasswordRequired));
        }
        return Err(format!("qpdf: {}", String::from_utf8_lossy(&output.stderr).trim()).into());
    }
    Ok(())
}

fn inherited(doc: &Document, id: ObjectId, key: &[u8]) -> Result<Object> {
    let mut current = id;
    let mut visited = HashSet::new();
    while visited.insert(current) {
        let dict = doc.get_dictionary(current)?;
        if let Ok(value) = dict.get(key) {
            return Ok(doc.dereference(value)?.1.clone());
        }
        current = match dict.get(b"Parent").and_then(Object::as_reference) {
            Ok(parent) => parent,
            Err(_) => break,
        };
    }
    Err(format!("PDF page is missing {}", String::from_utf8_lossy(key)).into())
}

fn geometry(doc: &Document, number: usize, id: ObjectId) -> Result<Page> {
    let media = inherited(doc, id, b"MediaBox")?;
    let crop = inherited(doc, id, b"CropBox").unwrap_or_else(|_| media.clone());
    let coords = |object: &Object| -> Result<Vec<f32>> {
        let values = object
            .as_array()?
            .iter()
            .map(Object::as_float)
            .collect::<lopdf::Result<Vec<_>>>()?;
        if values.len() != 4 || values.iter().any(|v| !v.is_finite()) {
            return Err("Invalid PDF page bounds".into());
        }
        Ok(values)
    };
    let m = coords(&media)?;
    let c = coords(&crop)?;
    let x = m[0].max(c[0]);
    let y = m[1].max(c[1]);
    let width = m[2].min(c[2]) - x;
    let height = m[3].min(c[3]) - y;
    if width <= 0.0 || height <= 0.0 {
        return Err("PDF page has an empty crop box".into());
    }
    let rotation = inherited(doc, id, b"Rotate")
        .ok()
        .and_then(|v| v.as_i64().ok())
        .unwrap_or(0)
        .rem_euclid(360);
    let (display_width, display_height, transform) = match rotation {
        0 => (width, height, [1.0, 0.0, 0.0, 1.0, x, y]),
        90 => (height, width, [0.0, 1.0, -1.0, 0.0, x + width, y]),
        180 => (width, height, [-1.0, 0.0, 0.0, -1.0, x + width, y + height]),
        270 => (height, width, [0.0, -1.0, 1.0, 0.0, x, y + height]),
        _ => return Err("PDF page rotation must be a multiple of 90 degrees".into()),
    };
    Ok(Page {
        number,
        width: display_width,
        height: display_height,
        id,
        transform,
    })
}

impl Session {
    fn open(path: &str, password: &str) -> Result<Self> {
        let source = fs::canonicalize(path)?;
        if !source.is_file() {
            return Err("Choose a PDF file".into());
        }
        let runtime = std::env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .filter(|path| path.is_dir())
            .unwrap_or_else(std::env::temp_dir);
        // TempDir creates a private 0700 directory, cleaned on stdin EOF/normal exit.
        let dir = tempfile::Builder::new()
            .prefix("pdfseal-")
            .tempdir_in(runtime)?;
        let snapshot = dir.path().join("document.pdf");
        qpdf(json!({
            "inputFile": source, "outputFile": snapshot, "password": password,
            "decrypt": ""
        }))?;
        let document = Document::load(&snapshot)?;
        let pages = document
            .get_pages()
            .into_iter()
            .map(|(number, id)| geometry(&document, number as usize, id))
            .collect::<Result<Vec<_>>>()?;
        if pages.is_empty() {
            return Err("This PDF contains no pages".into());
        }
        Ok(Self {
            dir,
            source,
            snapshot,
            document,
            pages,
            previews: VecDeque::new(),
        })
    }

    fn render(&mut self, number: usize, pixels: u32) -> Result<Value> {
        if number == 0 || number > self.pages.len() {
            return Err("Page is out of range".into());
        }
        // Bound each decoded preview and keep only 12 recent files.
        let pixels = pixels.clamp(600, 2600);
        let prefix = self.dir.path().join(format!("page-{number}-{pixels}"));
        let image = prefix.with_extension("png");
        let cached = image.is_file();
        if !cached {
            let output = Command::new("pdftoppm")
                .args([
                    "-f",
                    &number.to_string(),
                    "-l",
                    &number.to_string(),
                    "-scale-to",
                    &pixels.to_string(),
                    "-cropbox",
                    "-singlefile",
                    "-png",
                ])
                .arg(&self.snapshot)
                .arg(&prefix)
                .stdin(Stdio::null())
                .output()
                .map_err(|e| {
                    format!("Could not start pdftoppm: {e}. Install the poppler package.")
                })?;
            if !output.status.success() {
                return Err(format!(
                    "Could not render this page: {}",
                    String::from_utf8_lossy(&output.stderr).trim()
                )
                .into());
            }
        }
        self.previews.retain(|path| path != &image);
        self.previews.push_back(image.clone());
        while self.previews.len() > 12 {
            if let Some(old) = self.previews.pop_front() {
                let _ = fs::remove_file(old);
            }
        }
        Ok(json!({ "path": image, "page": number, "pixels": pixels, "cached": cached }))
    }

    fn export(&self, request: &Value) -> Result<Value> {
        let output = PathBuf::from(required_str(request, "path")?);
        if !output.is_absolute() {
            return Err("Export requires an absolute file path".into());
        }
        if fs::canonicalize(&output).ok().as_ref() == Some(&self.source) {
            return Err("Choose a new filename to preserve the original PDF".into());
        }
        let pages: Vec<PageSelection> = serde_json::from_value(request["pages"].clone())?;
        let marks: Vec<Mark> = serde_json::from_value(request["marks"].clone())?;
        if pages.is_empty() {
            return Err("Keep at least one page".into());
        }
        let mut seen = HashSet::new();
        for page in &pages {
            if page.number == 0
                || page.number > self.pages.len()
                || !seen.insert(page.number)
                || ![0, 90, 180, 270].contains(&page.rotation)
            {
                return Err("Invalid page selection or rotation".into());
            }
        }
        let mut doc = self.document.clone();
        for page in &self.pages {
            let page_marks = marks
                .iter()
                .filter(|mark| mark.page == page.number)
                .collect::<Vec<_>>();
            if !page_marks.is_empty() {
                annotate(&mut doc, page, &page_marks)?;
            }
        }
        let annotated = self.dir.path().join("annotated.pdf");
        doc.save(&annotated)?;
        let parent = output.parent().ok_or("Invalid export folder")?;
        let temporary = NamedTempFile::new_in(parent)?;
        let range = pages
            .iter()
            .map(|p| p.number.to_string())
            .collect::<Vec<_>>()
            .join(",");
        let rotations = pages
            .iter()
            .enumerate()
            .filter(|(_, p)| p.rotation != 0)
            .map(|(index, p)| format!("+{}:{}", p.rotation, index + 1))
            .collect::<Vec<_>>();
        let mut job = json!({
            "inputFile": annotated, "outputFile": temporary.path(),
            "pages": [{ "file": ".", "range": range }], "rotate": rotations
        });
        if request["compress"].as_bool().unwrap_or(false) {
            job["objectStreams"] = json!("generate");
            job["compressStreams"] = json!("y");
            job["recompressFlate"] = json!("");
            job["compressionLevel"] = json!("9");
        }
        let password = request["password"].as_str().unwrap_or("");
        if !password.is_empty() {
            job["encrypt"] =
                json!({ "userPassword": password, "ownerPassword": password, "256bit": {} });
        }
        qpdf(job)?;
        temporary.as_file().sync_all()?;
        let bytes = temporary.as_file().metadata()?.len();
        temporary.persist(&output).map_err(|e| e.error)?;
        Ok(json!({ "path": output, "bytes": bytes }))
    }
}

fn required_str<'a>(request: &'a Value, key: &str) -> Result<&'a str> {
    request[key]
        .as_str()
        .ok_or_else(|| format!("Missing {key}").into())
}

fn color(value: &str) -> Result<Vec<Object>> {
    if value.len() != 7
        || !value.starts_with('#')
        || !value[1..].bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err("Use a six-digit ink color".into());
    }
    (0..3)
        .map(|index| {
            let channel = u8::from_str_radix(&value[1 + index * 2..3 + index * 2], 16)?;
            Ok(Object::Real(channel as f32 / 255.0))
        })
        .collect()
}

fn op(name: &str, values: &[f32]) -> Operation {
    Operation::new(name, values.iter().copied().map(Object::Real).collect())
}

/// A Form XObject isolates our font/opacity/graphics state from the source PDF.
fn annotate(doc: &mut Document, page: &Page, marks: &[&Mark]) -> Result<()> {
    let mut operations = vec![];
    let mut image_resources = dictionary! {};
    for mark in marks {
        let values = [mark.x, mark.y, mark.w, mark.h];
        if values
            .iter()
            .any(|v| !v.is_finite() || *v < 0.0 || *v > 1.0)
            || !mark.size.is_finite()
            || !(0.1..=96.0).contains(&mark.size)
            || mark
                .points
                .iter()
                .flatten()
                .any(|v| !v.is_finite() || *v < 0.0 || *v > 1.0)
        {
            return Err("Invalid annotation coordinates".into());
        }
        operations.push(op("q", &[]));
        operations.push(Operation::new("RG", color(&mark.color)?));
        operations.push(Operation::new("rg", color(&mark.color)?));
        operations.push(op("w", &[mark.size]));
        operations.push(op("J", &[1.0]));
        operations.push(op("j", &[1.0]));
        let x = mark.x * page.width;
        let y = (1.0 - mark.y) * page.height;
        match mark.kind.as_str() {
            "image" => {
                if mark.w <= 0.0 || mark.h <= 0.0 || !mark.image_data.starts_with("data:image/") {
                    return Err("Invalid image annotation".into());
                }
                let id = images::embed(doc, &mark.image_data)?;
                let name = format!("Image_{}", id.0);
                image_resources.set(name.as_bytes(), id);
                operations.push(op(
                    "cm",
                    &[
                        mark.w * page.width,
                        0.0,
                        0.0,
                        mark.h * page.height,
                        x,
                        y - mark.h * page.height,
                    ],
                ));
                operations.push(Operation::new("Do", vec![Object::Name(name.into_bytes())]));
            }
            "ink" => {
                if mark.points.len() < 2 || mark.points.len() > 100_000 {
                    return Err("Ink strokes need between 2 and 100000 points".into());
                }
                for (index, point) in mark.points.iter().enumerate() {
                    operations.push(op(
                        if index == 0 { "m" } else { "l" },
                        &[point[0] * page.width, (1.0 - point[1]) * page.height],
                    ));
                }
                operations.push(op("S", &[]));
            }
            "box" | "highlight" => {
                if mark.kind == "highlight" {
                    operations.push(Operation::new("gs", vec!["Highlight".into()]));
                }
                operations.push(op(
                    "re",
                    &[
                        x,
                        y - mark.h * page.height,
                        mark.w * page.width,
                        mark.h * page.height,
                    ],
                ));
                operations.push(op(if mark.kind == "box" { "S" } else { "f" }, &[]));
            }
            "text" => {
                let (encoded, _, had_errors) = WINDOWS_1252.encode(&mark.text);
                if had_errors || mark.text.contains('\r') {
                    return Err("Text currently supports Western European characters".into());
                }
                operations.push(op("BT", &[]));
                let font = match mark.font.as_str() {
                    "" | "sans" => "Text",
                    "serif" => "Serif",
                    "mono" => "Mono",
                    _ => return Err("Unknown text font".into()),
                };
                operations.push(Operation::new("Tf", vec![font.into(), mark.size.into()]));
                operations.push(op("Td", &[x, y - mark.size]));
                for (index, line) in encoded.split(|byte| *byte == b'\n').enumerate() {
                    if index > 0 {
                        operations.push(op("Td", &[0.0, -mark.size * 1.2]));
                    }
                    operations.push(Operation::new("Tj", vec![Object::string_literal(line)]));
                }
                operations.push(op("ET", &[]));
            }
            _ => return Err("Unknown annotation type".into()),
        }
        operations.push(op("Q", &[]));
    }
    let font = doc.add_object(dictionary! {
        "Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica", "Encoding" => "WinAnsiEncoding"
    });
    let serif = doc.add_object(dictionary! {
        "Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Times-Roman", "Encoding" => "WinAnsiEncoding"
    });
    let mono = doc.add_object(dictionary! {
        "Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Courier", "Encoding" => "WinAnsiEncoding"
    });
    let form = Stream::new(
        dictionary! {
            "Type" => "XObject", "Subtype" => "Form", "FormType" => 1,
            "BBox" => vec![0.into(), 0.into(), page.width.into(), page.height.into()],
            "Resources" => dictionary! {
                "XObject" => image_resources,
                "Font" => dictionary! { "Text" => font, "Serif" => serif, "Mono" => mono },
                "ExtGState" => dictionary! {
                    "Highlight" => dictionary! { "Type" => "ExtGState", "ca" => 0.3, "BM" => "Multiply" }
                }
            }
        },
        Content { operations }.encode()?,
    );
    let form_id = doc.add_object(form);
    // Copy inherited resources before adding a page-local entry. This avoids
    // hiding a parent's fonts or changing a shared XObject dictionary.
    let mut resources = inherited(doc, page.id, b"Resources")
        .unwrap_or_else(|_| dictionary! {}.into())
        .as_dict()?
        .clone();
    let mut xobjects = match resources.get(b"XObject") {
        Ok(object) => doc.dereference(object)?.1.as_dict()?.clone(),
        Err(_) => dictionary! {},
    };
    let name = format!("PDFSeal_{}", form_id.0);
    xobjects.set(name.as_bytes(), form_id);
    resources.set("XObject", xobjects);
    doc.get_object_mut(page.id)?
        .as_dict_mut()?
        .set("Resources", resources);
    // Wrap original contents separately so its final CTM cannot affect our marks.
    let original = doc.get_page_contents(page.id);
    let before = doc.add_object(Stream::new(dictionary! {}, b"q\n".to_vec()));
    let after = doc.add_object(Stream::new(dictionary! {}, b"\nQ\n".to_vec()));
    let overlay = Content {
        operations: vec![
            op("q", &[]),
            op("cm", &page.transform),
            Operation::new("Do", vec![Object::Name(name.into_bytes())]),
            op("Q", &[]),
        ],
    }
    .encode()?;
    let overlay_id = doc.add_object(Stream::new(dictionary! {}, overlay));
    let contents = std::iter::once(before)
        .chain(original)
        .chain([after, overlay_id])
        .map(Object::Reference)
        .collect::<Vec<_>>();
    doc.get_object_mut(page.id)?
        .as_dict_mut()?
        .set("Contents", contents);
    Ok(())
}

fn dispatch(session: &mut Option<Session>, request: &Value) -> Result<Value> {
    match required_str(request, "op")? {
        "open" => {
            let next = Session::open(
                required_str(request, "path")?,
                request["password"].as_str().unwrap_or(""),
            )?;
            let result = json!({ "pages": next.pages, "path": next.source });
            *session = Some(next);
            Ok(result)
        }
        "render" => session.as_mut().ok_or("Open a PDF first")?.render(
            request["page"].as_u64().ok_or("Missing page number")? as usize,
            request["pixels"].as_u64().unwrap_or(1600).min(2600) as u32,
        ),
        "export" => session.as_ref().ok_or("Open a PDF first")?.export(request),
        "image" => images::prepare(required_str(request, "source")?),
        "close" => {
            *session = None;
            Ok(json!({}))
        }
        _ => Err("Unknown PDF operation".into()),
    }
}

fn main() -> Result<()> {
    if std::env::args().any(|arg| arg == "--version") {
        println!("pdfseal-worker {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let mut session = None;
    println!(
        "{}",
        json!({ "event": "ready", "version": env!("CARGO_PKG_VERSION") })
    );
    io::stdout().flush()?;
    for line in io::stdin().lock().lines() {
        let line = line?;
        let response = match serde_json::from_str::<Value>(&line) {
            Ok(request) => match dispatch(&mut session, &request) {
                Ok(result) => {
                    json!({ "id": request["id"], "op": request["op"], "ok": true, "result": result })
                }
                Err(error) => {
                    json!({ "id": request["id"], "op": request["op"], "ok": false, "error": error.to_string(), "passwordRequired": error.downcast_ref::<PasswordRequired>().is_some() })
                }
            },
            Err(_) => json!({ "ok": false, "error": "Invalid JSON request" }),
        };
        println!("{response}");
        io::stdout().flush()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(path: &Path) {
        let mut doc = Document::with_version("1.7");
        let pages = doc.new_object_id();
        let font = doc.add_object(
            dictionary! { "Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica" },
        );
        let resources = doc.add_object(dictionary! { "Font" => dictionary! { "F1" => font } });
        let content = doc.add_object(Stream::new(
            dictionary! {},
            b"BT /F1 20 Tf 40 100 Td (Original content) Tj ET".to_vec(),
        ));
        let page1 = doc.add_object(dictionary! {
            "Type" => "Page", "Parent" => pages, "Contents" => content,
            "CropBox" => vec![20.into(), 30.into(), 420.into(), 630.into()]
        });
        let page2 = doc.add_object(dictionary! {
            "Type" => "Page", "Parent" => pages, "Contents" => content, "Rotate" => 90
        });
        doc.objects.insert(pages, dictionary! {
            "Type" => "Pages", "Kids" => vec![page1.into(), page2.into()], "Count" => 2,
            "MediaBox" => vec![0.into(), 0.into(), 500.into(), 700.into()], "Resources" => resources
        }.into());
        let catalog = doc.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages });
        doc.trailer.set("Root", catalog);
        doc.save(path).unwrap();
    }

    #[test]
    fn native_roundtrip_preserves_original_content_and_geometry() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("original with spaces.pdf");
        fixture(&source);
        let original = fs::read(&source).unwrap();
        let mut session = Session::open(source.to_str().unwrap(), "").unwrap();
        assert_eq!(
            (session.pages[0].width, session.pages[0].height),
            (400.0, 600.0)
        );
        assert_eq!(
            (session.pages[1].width, session.pages[1].height),
            (700.0, 500.0)
        );
        let first = session.render(1, 600).unwrap();
        assert_eq!(first["cached"], false);
        assert_eq!(session.render(1, 600).unwrap()["cached"], true);
        let output = dir.path().join("signed.pdf");
        session.export(&json!({
            "path": output, "pages": [{"number": 2, "rotation": 90}, {"number": 1}],
            "compress": true, "marks": [
                {"page": 1, "kind": "text", "font": "serif", "color": "#153355", "size": 18, "x": 0.2, "y": 0.2, "text": "Signed by PDFSeal\nSecond line"},
                {"page": 1, "kind": "ink", "color": "#153355", "points": [[0.1,0.5],[0.3,0.55],[0.5,0.4]]},
                {"page": 1, "kind": "highlight", "color": "#ffcc00", "x":0.1,"y":0.3,"w":0.4,"h":0.1}
            ]
        })).unwrap();
        assert_eq!(fs::read(&source).unwrap(), original);
        let exported = Document::load(&output).unwrap();
        assert_eq!(exported.get_pages().len(), 2);
        let text_output = Command::new("pdftotext")
            .args(["-f", "2", "-l", "2"])
            .arg(&output)
            .arg("-")
            .output()
            .unwrap();
        assert!(text_output.status.success());
        let text = String::from_utf8_lossy(&text_output.stdout);
        assert!(text.contains("Original content"), "{text}");
        assert!(text.contains("Signed by PDFSeal"), "{text}");
        assert!(text.contains("Second line"), "{text}");
        let fonts = Command::new("pdffonts").arg(&output).output().unwrap();
        assert!(String::from_utf8_lossy(&fonts.stdout).contains("Times-Roman"));
        assert!(
            Command::new("qpdf")
                .arg("--check")
                .arg(&output)
                .output()
                .unwrap()
                .status
                .success()
        );
        let private = session.dir.path().to_path_buf();
        drop(session);
        assert!(!private.exists());
    }

    #[test]
    fn password_export_and_input_protection() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.pdf");
        fixture(&source);
        let session = Session::open(source.to_str().unwrap(), "").unwrap();
        let mut request = json!({ "path": source, "pages": [{"number":1}], "marks": [] });
        assert!(session.export(&request).is_err());
        request["path"] = json!(dir.path().join("encrypted.pdf"));
        request["password"] = json!("test ' $ password");
        session.export(&request).unwrap();
        assert!(Session::open(request["path"].as_str().unwrap(), "wrong").is_err());
        assert_eq!(
            Session::open(request["path"].as_str().unwrap(), "test ' $ password")
                .unwrap()
                .pages
                .len(),
            1
        );
    }

    #[test]
    fn malformed_commands_do_not_terminate_session() {
        let mut session = None;
        assert!(dispatch(&mut session, &json!({"op":"render","page":1})).is_err());
        assert!(dispatch(&mut session, &json!({"op":"shell","command":"anything"})).is_err());
        assert!(color("#💜!").is_err());
        assert!(color("#12345g").is_err());
        assert!(color("#aabbcc").is_ok());
    }
}
