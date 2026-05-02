import os
import io
from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from converter import docx_to_pdf, image_to_pdf
from editor import edit_pdf

app = FastAPI(title="WinSAS API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,   # must be False when allow_origins=["*"]
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"],
)

ALLOWED_TYPES = {
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "image/jpeg": "image",
    "image/jpg": "image",
    "image/png": "image",
    "image/webp": "image",
}

MAX_SIZE_MB = 20

# @app.get("/")
# def root():
#     return {"status": "DocConvert API is running"}

@app.get("/")
def health():
    return {"status": "ok", "service": "word-to-pdf"}


@app.post("/convert")
async def convert(file: UploadFile = File(...)):
    # Validate content type
    content_type = file.content_type or ""
    file_type = ALLOWED_TYPES.get(content_type)

    if not file_type:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type: {content_type}. Allowed: .docx, .jpg, .png, .webp"
        )

    # Read and size-check
    file_bytes = await file.read()
    size_mb = len(file_bytes) / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({size_mb:.1f} MB). Max is {MAX_SIZE_MB} MB."
        )

    # Convert
    try:
        if file_type == "docx":
            pdf_bytes = docx_to_pdf(file_bytes)
        else:
            pdf_bytes = image_to_pdf(file_bytes, file.filename or "image")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Conversion failed: {str(e)}")

    # Stream the PDF back
    original_name = os.path.splitext(file.filename or "converted")[0]
    output_name = f"{original_name}.pdf"

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{output_name}"'},
    )

@app.post("/edit")
async def edit(
        file: UploadFile = File(...),
        annotations: str = Form(...)
):
    pdf_bytes = await file.read()

    print(f"Received file: {file.filename}, size: {len(pdf_bytes)} bytes, type: {file.content_type}")
    print(f"Annotations: {annotations[:200]}")  # first 200 chars

    if len(pdf_bytes) == 0:
        raise HTTPException(status_code=400, detail="Received empty file")

    # Accept both pdf content types
    content_type = file.content_type or ""
    if "pdf" not in content_type and not (file.filename or "").endswith(".pdf"):
        raise HTTPException(
            status_code=415,
            detail=f"Only PDF files accepted. Got: {content_type}"
        )

    size_mb = len(pdf_bytes) / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({size_mb:.1f} MB). Max is {MAX_SIZE_MB} MB."
        )

    try:
        result_bytes = edit_pdf(pdf_bytes, annotations)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Edit failed: {str(e)}")

    original_name = os.path.splitext(file.filename or "edited")[0]
    return StreamingResponse(
        io.BytesIO(result_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{original_name}_edited.pdf"'
        },
    )