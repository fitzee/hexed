IMPLEMENTATION MODULE ReplaceState;

VAR
  rMode: BOOLEAN;
  rPhase: ReplacePhase;
  rSearchBuf: ARRAY [0..127] OF CHAR;
  rSearchLen: INTEGER;
  rReplaceBuf: ARRAY [0..127] OF CHAR;
  rReplaceLen: INTEGER;
  rIsHex: BOOLEAN;
  rNotFound: BOOLEAN;

PROCEDURE SetReplaceMode(on: BOOLEAN);
BEGIN
  rMode := on;
END SetReplaceMode;

PROCEDURE SetReplacePhase(p: ReplacePhase);
BEGIN
  rPhase := p;
END SetReplacePhase;

PROCEDURE SetSearchBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 127) DO
    rSearchBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 127 THEN rSearchBuf[i] := 0C; END;
  rSearchLen := len;
END SetSearchBuf;

PROCEDURE SetReplaceBuf(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < len) AND (i <= 127) DO
    rReplaceBuf[i] := buf[i];
    INC(i);
  END;
  IF i <= 127 THEN rReplaceBuf[i] := 0C; END;
  rReplaceLen := len;
END SetReplaceBuf;

PROCEDURE SetIsHex(hex: BOOLEAN);
BEGIN
  rIsHex := hex;
END SetIsHex;

PROCEDURE SetNotFound(nf: BOOLEAN);
BEGIN
  rNotFound := nf;
END SetNotFound;

PROCEDURE IsReplaceMode(): BOOLEAN;
BEGIN
  RETURN rMode;
END IsReplaceMode;

PROCEDURE GetReplacePhase(): ReplacePhase;
BEGIN
  RETURN rPhase;
END GetReplacePhase;

PROCEDURE GetSearchBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < rSearchLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := rSearchBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetSearchBuf;

PROCEDURE GetSearchLen(): INTEGER;
BEGIN
  RETURN rSearchLen;
END GetSearchLen;

PROCEDURE GetReplaceBuf(VAR buf: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < rReplaceLen) AND (i <= INTEGER(HIGH(buf))) DO
    buf[i] := rReplaceBuf[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(buf)) THEN buf[i] := 0C; END;
END GetReplaceBuf;

PROCEDURE GetReplaceLen(): INTEGER;
BEGIN
  RETURN rReplaceLen;
END GetReplaceLen;

PROCEDURE GetIsHex(): BOOLEAN;
BEGIN
  RETURN rIsHex;
END GetIsHex;

PROCEDURE ReplaceNotFound(): BOOLEAN;
BEGIN
  RETURN rNotFound;
END ReplaceNotFound;

BEGIN
  rMode := FALSE;
  rPhase := PhaseSearch;
  rSearchLen := 0;
  rReplaceLen := 0;
  rIsHex := TRUE;
  rNotFound := FALSE;
END ReplaceState.
