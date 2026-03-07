IMPLEMENTATION MODULE FontResolve;
FROM SYSTEM IMPORT ADR;
FROM Sys IMPORT m2sys_file_exists;

CONST
  NumPaths = 8;

VAR
  paths: ARRAY [0..NumPaths-1] OF ARRAY [0..127] OF CHAR;

PROCEDURE InitPaths;
BEGIN
  paths[0] := "resources/fonts/DejaVuSansMono.ttf";
  paths[1] := "/System/Library/Fonts/Menlo.ttc";
  paths[2] := "/System/Library/Fonts/Supplemental/Courier New.ttf";
  paths[3] := "/Library/Fonts/Courier New.ttf";
  paths[4] := "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";
  paths[5] := "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf";
  paths[6] := "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf";
  paths[7] := "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf";
END InitPaths;

PROCEDURE CopyStr(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i <= INTEGER(HIGH(src))) AND (i <= INTEGER(HIGH(dst))) AND (src[i] # 0C) DO
    dst[i] := src[i];
    INC(i);
  END;
  IF i <= INTEGER(HIGH(dst)) THEN dst[i] := 0C; END;
END CopyStr;

PROCEDURE Resolve(VAR path: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER;
BEGIN
  InitPaths;
  FOR i := 0 TO NumPaths-1 DO
    IF m2sys_file_exists(ADR(paths[i])) # 0 THEN
      CopyStr(path, paths[i]);
      RETURN TRUE;
    END;
  END;
  RETURN FALSE;
END Resolve;

END FontResolve.
