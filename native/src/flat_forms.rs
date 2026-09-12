//! Conservative, local detection of light form boxes and underline rules.
use crate::*;

#[derive(Clone)]
struct State {
    matrix: [f32; 6],
    fill: [f32; 3],
}
fn multiply(a: [f32; 6], b: [f32; 6]) -> [f32; 6] {
    [
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
    ]
}

pub fn detect(doc: &Document, pages: &[Page]) -> Result<Vec<forms::Field>> {
    let mut fields = Vec::<forms::Field>::new();
    for page in pages {
        jobs::check()?;
        // Same conservative restriction as Privseal: rotated flat forms use Text.
        if page.transform[0] != 1. || page.transform[3] != 1. {
            continue;
        }
        let Ok(content) = doc
            .get_page_content(page.id)
            .and_then(|bytes| Content::decode(&bytes))
        else {
            continue;
        };
        let mut state = State {
            matrix: [1., 0., 0., 1., 0., 0.],
            fill: [0.; 3],
        };
        let mut stack = vec![];
        let mut path = Vec::<(f32, f32)>::new();
        for operation in content.operations {
            let values: Vec<f32> = operation
                .operands
                .iter()
                .filter_map(|o| o.as_float().ok())
                .collect();
            match operation.operator.as_str() {
                "q" => stack.push(state.clone()),
                "Q" => {
                    if let Some(previous) = stack.pop() {
                        state = previous;
                    }
                }
                "cm" if values.len() == 6 => {
                    state.matrix = multiply(state.matrix, values.try_into().unwrap())
                }
                "rg" if values.len() == 3 => state.fill = values.try_into().unwrap(),
                "g" if values.len() == 1 => state.fill = [values[0]; 3],
                "k" if values.len() == 4 => {
                    state.fill = [
                        1. - (values[0] + values[3]).min(1.),
                        1. - (values[1] + values[3]).min(1.),
                        1. - (values[2] + values[3]).min(1.),
                    ]
                }
                "re" | "m" | "l" | "c" | "v" | "y" => {
                    let coords = if operation.operator == "re" && values.len() == 4 {
                        vec![
                            values[0],
                            values[1],
                            values[0] + values[2],
                            values[1],
                            values[0],
                            values[1] + values[3],
                            values[0] + values[2],
                            values[1] + values[3],
                        ]
                    } else {
                        values
                    };
                    let m = state.matrix;
                    for pair in coords.as_chunks::<2>().0 {
                        path.push((
                            m[0] * pair[0] + m[2] * pair[1] + m[4],
                            m[1] * pair[0] + m[3] * pair[1] + m[5],
                        ));
                    }
                }
                "f" | "f*" | "F" | "B" | "B*" | "b" | "b*" | "S" | "s" => {
                    if !path.is_empty() {
                        let mut rect = [
                            path.iter().map(|p| p.0).fold(f32::INFINITY, f32::min),
                            path.iter().map(|p| p.1).fold(f32::INFINITY, f32::min),
                            path.iter().map(|p| p.0).fold(f32::NEG_INFINITY, f32::max),
                            path.iter().map(|p| p.1).fold(f32::NEG_INFINITY, f32::max),
                        ];
                        let (w, h) = (rect[2] - rect[0], rect[3] - rect[1]);
                        let lum =
                            state.fill[0] * 0.299 + state.fill[1] * 0.587 + state.fill[2] * 0.114;
                        let light = (0.45..0.985).contains(&lum)
                            && !state.fill.iter().all(|v| *v > 247. / 255.);
                        let kind = if matches!(operation.operator.as_str(), "S" | "s") {
                            if h <= 3. && (24. ..=540.).contains(&w) {
                                rect[3] = rect[1] + 16.;
                                Some("text")
                            } else {
                                None
                            }
                        } else if light {
                            if (7. ..=24.).contains(&w)
                                && (7. ..=24.).contains(&h)
                                && (0.6..1.7).contains(&(w / h))
                            {
                                Some("checkbox")
                            } else if (24. ..=540.).contains(&w)
                                && (9. ..=46.).contains(&h)
                                && w / h >= 1.5
                            {
                                Some("text")
                            } else {
                                None
                            }
                        } else {
                            None
                        };
                        if let Some(kind) = kind {
                            let [x, y, w, h] = forms::normalized_rect(page, &rect)?;
                            if w > 0.
                                && h > 0.
                                && !fields.iter().any(|f| {
                                    f.page == page.number
                                        && (f.x - x).abs() < 0.01
                                        && (f.y - y).abs() < 0.01
                                        && (f.w - w).abs() < 0.01
                                })
                            {
                                fields.push(forms::Field::flat(
                                    fields.len(),
                                    page.number,
                                    kind,
                                    [x, y, w, h],
                                ));
                                if fields.len() >= 300 {
                                    return Ok(fields);
                                }
                            }
                        }
                    }
                    path.clear();
                }
                "n" => path.clear(),
                _ => {}
            }
        }
    }
    Ok(fields)
}

pub fn fill(
    doc: &mut Document,
    pages: &[Page],
    fields: &[forms::Field],
    values: &Value,
) -> Result<()> {
    for page in pages {
        let mut marks = vec![];
        for field in fields.iter().filter(|f| f.page == page.number) {
            let Some(value) = values[&field.name].as_str().filter(|s| !s.is_empty()) else {
                continue;
            };
            let height = field.h * page.height;
            let size = if field.kind == "checkbox" {
                (height * 0.95).clamp(8., 15.)
            } else {
                (height * 0.66).clamp(8., 16.)
            };
            marks.push(serde_json::from_value::<Mark>(json!({"page":page.number,"kind":"text","color":"#211d17","size":size,"x":field.x+2./page.width,"y":field.y+(height-size).max(0.)/2./page.height,"text":if field.kind=="checkbox"{"X"}else{value},"font":"sans"}))?);
        }
        if !marks.is_empty() {
            annotate(doc, page, &marks.iter().collect::<Vec<_>>())?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn detects_light_boxes_and_rules_and_bakes_values() {
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("flat.pdf");
        crate::tests::fixture(&input);
        let session = Session::open(input.to_str().unwrap(), "").unwrap();
        let mut doc = session.document.clone();
        let page = &session.pages[0];
        doc.add_page_contents(page.id,b"q 0.9 g 40 60 120 20 re f 200 60 12 12 re f 0 G 40 120 m 200 120 l S 1 g 40 160 120 20 re f Q".to_vec()).unwrap();
        let fields = detect(&doc, &session.pages).unwrap();
        assert_eq!(fields.len(), 3);
        assert_eq!(fields[1].kind, "checkbox");
        let values = json!({fields[0].name.clone():"Flat value",fields[1].name.clone():"Yes"});
        fill(&mut doc, &session.pages, &fields, &values).unwrap();
        let output = dir.path().join("filled.pdf");
        doc.save(&output).unwrap();
        let text = Command::new("pdftotext")
            .arg(&output)
            .arg("-")
            .output()
            .unwrap();
        assert!(String::from_utf8_lossy(&text.stdout).contains("Flat value"));
        assert!(String::from_utf8_lossy(&text.stdout).contains('X'));
    }
}
