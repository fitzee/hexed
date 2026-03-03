IMPLEMENTATION MODULE Cmd;

FROM ByteStore IMPORT SetByte;

PROCEDURE Init(VAR h: CmdHistory);
BEGIN
  h.count := 0;
  h.pos := 0;
  h.curGroup := 0;
  h.nextGroup := 0;
END Init;

PROCEDURE BeginGroup(VAR h: CmdHistory);
BEGIN
  INC(h.nextGroup);
  h.curGroup := h.nextGroup;
END BeginGroup;

PROCEDURE EndGroup(VAR h: CmdHistory);
BEGIN
  h.curGroup := 0;
END EndGroup;

PROCEDURE RecordSetByte(VAR h: CmdHistory; off, oldVal, newVal: CARDINAL);
BEGIN
  IF h.pos < MaxCmds THEN
    h.cmds[h.pos].kind := CmdSetByte;
    h.cmds[h.pos].offset := off;
    h.cmds[h.pos].oldVal := oldVal;
    h.cmds[h.pos].newVal := newVal;
    h.cmds[h.pos].group := h.curGroup;
    INC(h.pos);
    h.count := h.pos;
  END;
END RecordSetByte;

PROCEDURE Undo(VAR h: CmdHistory; VAR s: Store): BOOLEAN;
VAR g: CARDINAL;
BEGIN
  IF h.pos = 0 THEN RETURN FALSE; END;
  DEC(h.pos);
  g := h.cmds[h.pos].group;
  IF h.cmds[h.pos].kind = CmdSetByte THEN
    SetByte(s, h.cmds[h.pos].offset, h.cmds[h.pos].oldVal);
  END;
  (* If grouped, keep undoing all commands in the same group *)
  IF g # 0 THEN
    WHILE (h.pos > 0) AND (h.cmds[h.pos - 1].group = g) DO
      DEC(h.pos);
      IF h.cmds[h.pos].kind = CmdSetByte THEN
        SetByte(s, h.cmds[h.pos].offset, h.cmds[h.pos].oldVal);
      END;
    END;
  END;
  RETURN TRUE;
END Undo;

PROCEDURE Redo(VAR h: CmdHistory; VAR s: Store): BOOLEAN;
VAR g: CARDINAL;
BEGIN
  IF h.pos >= h.count THEN RETURN FALSE; END;
  g := h.cmds[h.pos].group;
  IF h.cmds[h.pos].kind = CmdSetByte THEN
    SetByte(s, h.cmds[h.pos].offset, h.cmds[h.pos].newVal);
  END;
  INC(h.pos);
  (* If grouped, keep redoing all commands in the same group *)
  IF g # 0 THEN
    WHILE (h.pos < h.count) AND (h.cmds[h.pos].group = g) DO
      IF h.cmds[h.pos].kind = CmdSetByte THEN
        SetByte(s, h.cmds[h.pos].offset, h.cmds[h.pos].newVal);
      END;
      INC(h.pos);
    END;
  END;
  RETURN TRUE;
END Redo;

PROCEDURE CanUndo(VAR h: CmdHistory): BOOLEAN;
BEGIN
  RETURN h.pos > 0;
END CanUndo;

PROCEDURE CanRedo(VAR h: CmdHistory): BOOLEAN;
BEGIN
  RETURN h.pos < h.count;
END CanRedo;

END Cmd.
