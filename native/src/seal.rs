//! Detached CMS seals. Credentials stay in memory; signing is the last mutation.
use crate::*;
use openssl::{
    asn1::Asn1Time,
    bn::{BigNum, MsbOption},
    hash::MessageDigest,
    pkcs7::{Pkcs7, Pkcs7Flags},
    pkcs12::Pkcs12,
    pkey::{PKey, Private},
    rsa::Rsa,
    stack::Stack,
    x509::{X509, X509NameBuilder, store::X509StoreBuilder},
};
use std::path::Path;

struct Credentials {
    key: PKey<Private>,
    cert: X509,
    chain: Stack<X509>,
}
fn credentials(options: &Value) -> Result<Credentials> {
    if let Some(path) = options["p12"].as_str().filter(|s| !s.is_empty()) {
        if fs::metadata(path)?.len() > 16 * 1024 * 1024 {
            return Err("Certificate bundle is too large".into());
        }
        let bytes = fs::read(path)?;
        let parsed = Pkcs12::from_der(&bytes)?
            .parse2(options["password"].as_str().unwrap_or(""))
            .map_err(|_| "Could not open this .p12/.pfx: wrong password or unsupported format")?;
        let key = parsed.pkey.ok_or("Certificate bundle has no private key")?;
        let cert = parsed
            .cert
            .ok_or("Certificate bundle has no signing certificate")?;
        if !key.public_eq(cert.public_key()?.as_ref()) {
            return Err("Certificate does not match its private key".into());
        }
        return Ok(Credentials {
            key,
            cert,
            chain: parsed.ca.unwrap_or(Stack::new()?),
        });
    }
    let name = options["name"]
        .as_str()
        .filter(|s| !s.trim().is_empty())
        .ok_or("Enter a signer name")?;
    if name.len() > 256 {
        return Err("Signer name is too long".into());
    }
    jobs::progress(1, 3, "Creating local signing certificate")?;
    let key = PKey::from_rsa(Rsa::generate(2048)?)?;
    let mut subject = X509NameBuilder::new()?;
    subject.append_entry_by_text("CN", name)?;
    let subject = subject.build();
    let mut cert = X509::builder()?;
    cert.set_version(2)?;
    let mut serial = BigNum::new()?;
    serial.rand(128, MsbOption::MAYBE_ZERO, false)?;
    cert.set_serial_number(serial.to_asn1_integer()?.as_ref())?;
    cert.set_subject_name(&subject)?;
    cert.set_issuer_name(&subject)?;
    cert.set_pubkey(&key)?;
    cert.set_not_before(Asn1Time::days_from_now(0)?.as_ref())?;
    cert.set_not_after(Asn1Time::days_from_now(365 * 5)?.as_ref())?;
    cert.sign(&key, MessageDigest::sha256())?;
    Ok(Credentials {
        key,
        cert: cert.build(),
        chain: Stack::new()?,
    })
}

pub fn has_signature(doc: &Document) -> bool {
    let flags = doc
        .catalog()
        .ok()
        .and_then(|d| d.get(b"AcroForm").ok())
        .and_then(|o| doc.dereference(o).ok())
        .and_then(|(_, o)| o.as_dict().ok())
        .and_then(|d| d.get(b"SigFlags").ok())
        .and_then(|o| o.as_i64().ok())
        .unwrap_or(0);
    flags & 1 != 0
        || doc.objects.values().any(|o| {
            o.as_dict().is_ok_and(|d| {
                d.get(b"Type").and_then(Object::as_name).ok() == Some(b"Sig")
                    || (d.get(b"FT").and_then(Object::as_name).ok() == Some(b"Sig") && d.has(b"V"))
            })
        })
}

fn find(bytes: &[u8], needle: &[u8]) -> Result<usize> {
    bytes
        .windows(needle.len())
        .position(|w| w == needle)
        .ok_or_else(|| "Could not locate PDF signature reservation".into())
}

pub fn sign(path: &Path, options: &Value) -> Result<()> {
    let mut doc = Document::load(path)?;
    if has_signature(&doc) {
        return Err(
            "This PDF already contains a digital signature. Resealing would invalidate it.".into(),
        );
    }
    if doc.is_encrypted() {
        return Err("Digital sealing requires an unencrypted export".into());
    }
    let credentials = credentials(options)?;
    jobs::progress(2, 3, "Creating PDF digital seal")?;
    const RESERVED: usize = 16384;
    let signature=doc.add_object(dictionary!{"Type"=>"Sig","Filter"=>"Adobe.PPKLite","SubFilter"=>"adbe.pkcs7.detached",
        "ByteRange"=>vec![Object::Integer(0),Object::Name(b"PDFSEAL_RANGE_A".to_vec()),Object::Name(b"PDFSEAL_RANGE_B".to_vec()),Object::Name(b"PDFSEAL_RANGE_C".to_vec())],
        "Contents"=>Object::String(vec![0;RESERVED],lopdf::StringFormat::Hexadecimal),
        "M"=>Object::string_literal(chrono::Utc::now().format("D:%Y%m%d%H%M%SZ").to_string()),
        "Name"=>text::pdf_string(options["name"].as_str().unwrap_or("PDFSeal signer")),
        "Reason"=>text::pdf_string(options["reason"].as_str().unwrap_or("")),
        "Location"=>text::pdf_string(options["location"].as_str().unwrap_or(""))});
    let page = *doc.get_pages().values().next().ok_or("No page to sign")?;
    let widget=doc.add_object(dictionary!{"Type"=>"Annot","Subtype"=>"Widget","FT"=>"Sig","Rect"=>vec![0.into(),0.into(),0.into(),0.into()],"V"=>signature,"T"=>Object::string_literal("PDFSealSignature"),"F"=>132,"P"=>page});
    let mut annots = doc
        .get_dictionary(page)?
        .get(b"Annots")
        .ok()
        .and_then(|o| doc.dereference(o).ok())
        .and_then(|(_, o)| o.as_array().ok())
        .cloned()
        .unwrap_or_default();
    annots.push(widget.into());
    doc.get_object_mut(page)?
        .as_dict_mut()?
        .set("Annots", annots);
    let mut form = doc
        .catalog()?
        .get(b"AcroForm")
        .ok()
        .and_then(|o| doc.dereference(o).ok())
        .and_then(|(_, o)| o.as_dict().ok())
        .cloned()
        .unwrap_or_default();
    let mut fields = form
        .get(b"Fields")
        .ok()
        .and_then(|o| doc.dereference(o).ok())
        .and_then(|(_, o)| o.as_array().ok())
        .cloned()
        .unwrap_or_default();
    fields.push(widget.into());
    form.set("Fields", fields);
    form.set("SigFlags", 3);
    let form = doc.add_object(form);
    doc.catalog_mut()?.set("AcroForm", form);
    let mut bytes = vec![];
    doc.save_to(&mut bytes)?;
    // Locate our new signature object, never an unrelated ByteRange in stream data.
    let parsed = Document::load_mem(&bytes)?;
    let object_start = match parsed.reference_table.get(signature.0) {
        Some(lopdf::xref::XrefEntry::Normal { offset, .. }) => *offset as usize,
        _ => return Err("Signature object must be uncompressed".into()),
    };
    let tail = &bytes[object_start..];
    let range_start = object_start + find(tail, b"/ByteRange[")? + b"/ByteRange".len();
    let range_end = range_start + find(&bytes[range_start..], b"]")?;
    let contents = object_start + find(tail, b"/Contents<")? + b"/Contents".len();
    let contents_end = contents + 1 + RESERVED * 2;
    if bytes[contents_end] != b'>' {
        return Err("Invalid signature reservation".into());
    }
    let range = [
        0,
        contents,
        contents_end + 1,
        bytes.len() - contents_end - 1,
    ];
    let numbers = format!("{} {} {} {}", range[0], range[1], range[2], range[3]);
    if numbers.len() > range_end - range_start - 1 {
        return Err("PDF is too large to seal".into());
    }
    bytes[range_start + 1..range_end].fill(b' ');
    bytes[range_start + 1..range_start + 1 + numbers.len()].copy_from_slice(numbers.as_bytes());
    let mut content = bytes[..contents].to_vec();
    content.extend_from_slice(&bytes[contents_end + 1..]);
    let cms = Pkcs7::sign(
        &credentials.cert,
        &credentials.key,
        &credentials.chain,
        &content,
        Pkcs7Flags::DETACHED | Pkcs7Flags::BINARY,
    )?;
    // Verify integrity using the embedded public key; this does not assert CA trust.
    cms.verify(
        Stack::new()?.as_ref(),
        &X509StoreBuilder::new()?.build(),
        Some(&content),
        None,
        Pkcs7Flags::NOVERIFY | Pkcs7Flags::BINARY,
    )?;
    let der = cms.to_der()?;
    if der.len() > RESERVED {
        return Err("Certificate chain exceeds the reserved signature space".into());
    }
    let hex = der.iter().map(|b| format!("{b:02x}")).collect::<String>();
    bytes[contents + 1..contents + 1 + hex.len()].copy_from_slice(hex.as_bytes());
    jobs::check()?;
    fs::write(path, bytes)?;
    jobs::progress(3, 3, "Digital seal verified")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn digital_seal_verifies_and_detects_tampering_with_p12_support() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sealed.pdf");
        crate::tests::fixture(&path);
        let options = json!({"name":"Test Signer","reason":"Local approval"});
        sign(&path, &options).unwrap();
        let check = Command::new("pdfsig").arg(&path).output().unwrap();
        let report = String::from_utf8_lossy(&check.stdout);
        assert!(report.contains("Signature is Valid"), "{report}");
        assert!(report.contains("SHA-256"), "{report}");
        assert!(report.contains("Total document signed"), "{report}");
        assert!(sign(&path, &options).is_err());
        let mut bytes = fs::read(&path).unwrap();
        let index = find(&bytes, b"PDFSealSignature").unwrap();
        bytes[index] = b'X';
        fs::write(&path, bytes).unwrap();
        let check = Command::new("pdfsig").arg(&path).output().unwrap();
        assert!(
            String::from_utf8_lossy(&check.stdout).contains("Digest Mismatch"),
            "{}",
            String::from_utf8_lossy(&check.stdout)
        );
        let credentials = credentials(&options).unwrap();
        let bundle = Pkcs12::builder()
            .name("Test")
            .pkey(&credentials.key)
            .cert(&credentials.cert)
            .build2("secret")
            .unwrap();
        let p12 = dir.path().join("test.p12");
        fs::write(&p12, bundle.to_der().unwrap()).unwrap();
        crate::tests::fixture(&path);
        assert!(
            sign(
                &path,
                &json!({"name":"Test Signer","p12":p12,"password":"wrong"})
            )
            .is_err()
        );
        sign(
            &path,
            &json!({"name":"Test Signer","p12":p12,"password":"secret"}),
        )
        .unwrap();
        let check = Command::new("pdfsig").arg(&path).output().unwrap();
        assert!(String::from_utf8_lossy(&check.stdout).contains("Signature is Valid"));
    }
}
