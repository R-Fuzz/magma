#!/bin/bash
set -e

pip install --no-cache-dir \
    google-auth \
    google-genai \
    openai \
    anthropic

# Install common external libs
pip install --no-cache-dir \
    asn1 \
    asn1crypto \
    asn1tools \
    crcmod \
    cryptography \
    numpy \
    opencv-python \
    pdfrw \
    PyPDF2 \
    pillow \
    pypng \
    pyasn1 \
    pyasn1-modules \
    pycryptodome \
    pytesseract \
    reportlab
