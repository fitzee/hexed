IMPLEMENTATION MODULE ExportState;

VAR
  eMode: BOOLEAN;
  eBuf: ARRAY [0..255] OF CHAR;
  eLen: INTEGER;
  eError: BOOLEAN;

PROCEDURE SetExportMode(on: BOOLEAN);
BEGIN
  eMode := on;
END SetExportMode;

PROCEDURE SetExportBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 255) DO
    eBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 255 THEN eBuf[i] := 0C; END;
  eLen := len;
END SetExportBuf;

PROCEDURE SetExportError(e: BOOLEAN);
BEGIN
  eError := e;
END SetExportError;

PROCEDURE IsExportMode(): BOOLEAN;
BEGIN
  RETURN eMode;
END IsExportMode;

PROCEDURE GetExportBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < eLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := eBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetExportBuf;

PROCEDURE GetExportLen(): INTEGER;
BEGIN
  RETURN eLen;
END GetExportLen;

PROCEDURE ExportError(): BOOLEAN;
BEGIN
  RETURN eError;
END ExportError;

BEGIN
  eMode := FALSE;
  eLen := 0;
  eError := FALSE;
END ExportState.
