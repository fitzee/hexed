IMPLEMENTATION MODULE GotoState;

VAR
  gMode: BOOLEAN;
  gBuf: ARRAY [0..31] OF CHAR;
  gLen: INTEGER;
  gError: BOOLEAN;

PROCEDURE SetGotoMode(on: BOOLEAN);
BEGIN
  gMode := on;
END SetGotoMode;

PROCEDURE SetGotoBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 31) DO
    gBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 31 THEN gBuf[i] := 0C; END;
  gLen := len;
END SetGotoBuf;

PROCEDURE SetGotoError(e: BOOLEAN);
BEGIN
  gError := e;
END SetGotoError;

PROCEDURE IsGotoMode(): BOOLEAN;
BEGIN
  RETURN gMode;
END IsGotoMode;

PROCEDURE GetGotoBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < gLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := gBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetGotoBuf;

PROCEDURE GetGotoLen(): INTEGER;
BEGIN
  RETURN gLen;
END GetGotoLen;

PROCEDURE GotoError(): BOOLEAN;
BEGIN
  RETURN gError;
END GotoError;

BEGIN
  gMode := FALSE;
  gLen := 0;
  gError := FALSE;
END GotoState.
