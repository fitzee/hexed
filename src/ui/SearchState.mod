IMPLEMENTATION MODULE SearchState;

VAR
  sMode: BOOLEAN;
  sBuf: ARRAY [0..127] OF CHAR;
  sLen: INTEGER;
  sIsHex: BOOLEAN;
  sNotFound: BOOLEAN;

PROCEDURE SetSearchMode(on: BOOLEAN);
BEGIN
  sMode := on;
END SetSearchMode;

PROCEDURE SetSearchBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 127) DO
    sBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 127 THEN sBuf[i] := 0C; END;
  sLen := len;
END SetSearchBuf;

PROCEDURE SetSearchIsHex(hex: BOOLEAN);
BEGIN
  sIsHex := hex;
END SetSearchIsHex;

PROCEDURE SetNotFound(nf: BOOLEAN);
BEGIN
  sNotFound := nf;
END SetNotFound;

PROCEDURE IsSearchMode(): BOOLEAN;
BEGIN
  RETURN sMode;
END IsSearchMode;

PROCEDURE GetSearchBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < sLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := sBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetSearchBuf;

PROCEDURE GetSearchLen(): INTEGER;
BEGIN
  RETURN sLen;
END GetSearchLen;

PROCEDURE GetSearchIsHex(): BOOLEAN;
BEGIN
  RETURN sIsHex;
END GetSearchIsHex;

PROCEDURE SearchNotFound(): BOOLEAN;
BEGIN
  RETURN sNotFound;
END SearchNotFound;

BEGIN
  sMode := FALSE;
  sLen := 0;
  sIsHex := TRUE;
  sNotFound := FALSE;
END SearchState.
