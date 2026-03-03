MODULE Main;
(* hexed — a cross-platform hex editor built in Modula-2+
   Usage: hexed <filename> *)

FROM Args IMPORT ArgCount, GetArg;
FROM InOut IMPORT WriteString, WriteLn;
FROM App IMPORT Run;

VAR
  path: ARRAY [0..1023] OF CHAR;
  rc: INTEGER;
BEGIN
  IF ArgCount() < 2 THEN
    WriteString("usage: hexed <filename>"); WriteLn;
    HALT;
  END;
  GetArg(1, path);
  rc := Run(path);
  IF rc # 0 THEN HALT; END;
END Main.
