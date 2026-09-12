use crate::Result;
use base64::{Engine, engine::general_purpose::STANDARD};
use image::{DynamicImage, ImageFormat, ImageReader, RgbaImage};
use lopdf::{Document, ObjectId, Stream, dictionary};
use serde_json::{Value, json};
use std::io::Cursor;

const MAX_BYTES: usize = 32 * 1024 * 1024;

pub fn decode(source: &str) -> Result<RgbaImage> {
    let bytes = if source.starts_with("data:image/") {
        let (header, data) = source.split_once(',').ok_or("Invalid image data")?;
        if !header.ends_with(";base64") || data.len() > MAX_BYTES * 4 / 3 + 8 {
            return Err("Use a PNG, JPEG or WebP image smaller than 32 MB".into());
        }
        STANDARD.decode(data)?
    } else {
        if !std::path::Path::new(source).is_absolute() {
            return Err("Choose a local image file".into());
        }
        if std::fs::metadata(source)?.len() > MAX_BYTES as u64 {
            return Err("Use an image smaller than 32 MB".into());
        }
        std::fs::read(source)?
    };
    let mut reader = ImageReader::new(Cursor::new(bytes)).with_guessed_format()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(256 * 1024 * 1024);
    reader.limits(limits);
    Ok(reader.decode()?.to_rgba8())
}

pub fn prepare(source: &str) -> Result<Value> {
    let image = decode(source)?;
    let (width, height) = image.dimensions();
    let (mut left, mut top, mut right, mut bottom) = (width, height, 0, 0);
    for (x, y, pixel) in image.enumerate_pixels() {
        if pixel[3] > 10 {
            left = left.min(x);
            top = top.min(y);
            right = right.max(x);
            bottom = bottom.max(y);
        }
    }
    if left == width {
        return Err("The signature is empty".into());
    }
    left = left.saturating_sub(6);
    top = top.saturating_sub(6);
    right = (right + 6).min(width - 1);
    bottom = (bottom + 6).min(height - 1);
    let cropped =
        image::imageops::crop_imm(&image, left, top, right - left + 1, bottom - top + 1).to_image();
    let mut image = DynamicImage::ImageRgba8(cropped);
    if image.width().max(image.height()) > 4096 {
        image = image.resize(4096, 4096, image::imageops::FilterType::Lanczos3);
    }
    let mut output = Cursor::new(Vec::new());
    image.write_to(&mut output, ImageFormat::Png)?;
    Ok(
        json!({"dataUrl": format!("data:image/png;base64,{}", STANDARD.encode(output.into_inner())), "width":image.width(), "height":image.height()}),
    )
}

pub fn embed(doc: &mut Document, source: &str) -> Result<ObjectId> {
    let image = decode(source)?;
    let (width, height) = image.dimensions();
    let mut rgb = Vec::with_capacity((width * height * 3) as usize);
    let mut alpha = Vec::with_capacity((width * height) as usize);
    for pixel in image.pixels() {
        rgb.extend_from_slice(&pixel.0[..3]);
        alpha.push(pixel[3]);
    }
    let mut dict = dictionary! {"Type"=>"XObject", "Subtype"=>"Image", "Width"=>width, "Height"=>height, "ColorSpace"=>"DeviceRGB", "BitsPerComponent"=>8};
    if alpha.iter().any(|byte| *byte != 255) {
        let mut mask = Stream::new(
            dictionary! {"Type"=>"XObject", "Subtype"=>"Image", "Width"=>width, "Height"=>height, "ColorSpace"=>"DeviceGray", "BitsPerComponent"=>8},
            alpha,
        );
        mask.compress()?;
        dict.set("SMask", doc.add_object(mask));
    }
    let mut image = Stream::new(dict, rgb);
    image.compress()?;
    Ok(doc.add_object(image))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trims_and_embeds_transparent_signature_without_white_background() {
        let mut pixels = RgbaImage::new(100, 50);
        for x in 20..80 {
            for y in 10..40 {
                pixels.put_pixel(x, y, image::Rgba([20, 50, 90, 255]));
            }
        }
        let mut png = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(pixels)
            .write_to(&mut png, ImageFormat::Png)
            .unwrap();
        let source = format!(
            "data:image/png;base64,{}",
            STANDARD.encode(png.into_inner())
        );
        let prepared = prepare(&source).unwrap();
        assert_eq!(
            (prepared["width"].as_u64(), prepared["height"].as_u64()),
            (Some(72), Some(42))
        );
        let url = prepared["dataUrl"].as_str().unwrap();
        assert_eq!(decode(url).unwrap().get_pixel(0, 0)[3], 0);
        let mut doc = Document::with_version("1.7");
        let id = embed(&mut doc, url).unwrap();
        let image = doc.get_object(id).unwrap().as_stream().unwrap();
        assert!(image.dict.has(b"SMask"));
        assert_eq!(image.dict.get(b"Width").unwrap().as_i64().unwrap(), 72);
    }

    #[test]
    fn refuses_empty_signature() {
        let mut png = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(RgbaImage::new(10, 10))
            .write_to(&mut png, ImageFormat::Png)
            .unwrap();
        let source = format!(
            "data:image/png;base64,{}",
            STANDARD.encode(png.into_inner())
        );
        assert!(prepare(&source).unwrap_err().to_string().contains("empty"));
    }
}
