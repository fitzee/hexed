IMPLEMENTATION MODULE FillState;

VAR
  fMode: BOOLEAN;
  fBuf: ARRAY [0..3] OF CHAR;
  fLen: INTEGER;

PROCEDURE SetFillMode(on: BOOLEAN);
BEGIN
  fMode := on;
END SetFillMode;

PROCEDURE SetFillBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 3) DO
    fBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 3 THEN fBuf[i] := 0C; END;
  fLen := len;
END SetFillBuf;

PROCEDURE IsFillMode(): BOOLEAN;
BEGIN
  RETURN fMode;
END IsFillMode;

PROCEDURE GetFillBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < fLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := fBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetFillBuf;

PROCEDURE GetFillLen(): INTEGER;
BEGIN
  RETURN fLen;
END GetFillLen;

BEGIN
  fMode := FALSE;
  fLen := 0;
END FillState.
