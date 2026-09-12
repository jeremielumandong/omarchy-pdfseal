use crate::Result;
use serde_json::json;
use std::io::{Read, Write};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

pub static CURRENT: AtomicU64 = AtomicU64::new(0);
pub static CANCELLED: AtomicU64 = AtomicU64::new(0);

pub fn check() -> Result<()> {
    let current = CURRENT.load(Ordering::Relaxed);
    if current != 0 && CANCELLED.load(Ordering::Relaxed) == current {
        return Err("Operation cancelled".into());
    }
    Ok(())
}

pub fn progress(current: usize, total: usize, stage: &str) -> Result<()> {
    check()?;
    let id = CURRENT.load(Ordering::Relaxed);
    if id != 0 {
        println!(
            "{}",
            json!({"event":"progress","id":id,"current":current,"total":total,"stage":stage})
        );
        std::io::stdout().flush()?;
    }
    Ok(())
}

/// Drain output while polling the owned child, allowing cancellation without
/// stopping the PDF session or exposing passwords in command arguments.
pub fn run(command: &mut Command, input: Option<&[u8]>) -> Result<Output> {
    check()?;
    let mut child = command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    let output_thread = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        stdout.read_to_end(&mut bytes).map(|_| bytes)
    });
    let error_thread = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        stderr.read_to_end(&mut bytes).map(|_| bytes)
    });
    let write = if let Some(bytes) = input {
        child.stdin.take().unwrap().write_all(bytes)
    } else {
        Ok(())
    };
    let mut cancelled = false;
    let status = loop {
        if check().is_err() {
            cancelled = true;
            let _ = child.kill();
            break child.wait()?;
        }
        if let Some(status) = child.try_wait()? {
            break status;
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let stdout = output_thread
        .join()
        .map_err(|_| "Could not read operation output")??;
    let stderr = error_thread
        .join()
        .map_err(|_| "Could not read operation error")??;
    if cancelled {
        return Err("Operation cancelled".into());
    }
    write?;
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}
