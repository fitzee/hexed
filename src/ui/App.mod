IMPLEMENTATION MODULE App;

FROM Gfx IMPORT Init, InitFont, Quit, QuitFont,
                CreateWindow, DestroyWindow, SetTitle,
                SetWindowMinSize,
                CreateRenderer, DestroyRenderer, Present,
                UpdateLogicalSize,
                GetWindowWidth, GetWindowHeight,
                WIN_CENTERED, WIN_RESIZABLE, WIN_HIGHDPI,
                RENDER_ACCELERATED, RENDER_VSYNC,
                Window, Renderer, Delay;
FROM Font IMPORT Open AS FontOpen, OpenPhysical, DpiScale,
                Close AS FontClose, FontHandle, SetHinting, HINT_MONO;
FROM Canvas IMPORT SetBlendMode, BLEND_NONE;
FROM Events IMPORT Poll, WaitTimeout, NONE, QUIT_EVENT, WINDOW_EVENT,
                   WindowEvent, WEVT_RESIZED, WEVT_EXPOSED, StartTextInput;
FROM Doc IMPORT Document, Open AS DocOpen, Close AS DocClose, IsDirty;
FROM View IMPORT ViewState, Init AS ViewInit, Resize, Render, MinWindowSize;
FROM Keymap IMPORT HandleEvent, Action, ActQuit, ActRedraw, ActZoomIn, ActZoomOut;
FROM Theme IMPORT Init AS ThemeInit;
FROM InOut IMPORT WriteString, WriteLn;
FROM FontResolve IMPORT Resolve AS ResolveFont;

CONST
  InitWidth  = 1100;
  InitHeight = 700;
  LogicalMin = 12;
  LogicalMax = 24;

VAR
  fontPath: ARRAY [0..255] OF CHAR;

PROCEDURE Run(path: ARRAY OF CHAR): INTEGER;
VAR
  win: Window;
  ren: Renderer;
  font: FontHandle;
  doc: Document;
  view: ViewState;
  evType: INTEGER;
  act: Action;
  running: BOOLEAN;
  needRedraw: BOOLEAN;
  wasDirty: BOOLEAN;
  physSize: INTEGER;
  minPhys, maxPhys: INTEGER;
  zoomDir: INTEGER;
  zoomHeld: BOOLEAN;
  newFont: FontHandle;
  winW, winH: INTEGER;
  mwW, mwH: INTEGER;
  titleBuf: ARRAY [0..511] OF CHAR;
BEGIN
  (* Initialize SDL *)
  IF NOT Init() THEN
    WriteString("error: SDL init failed"); WriteLn;
    RETURN 1;
  END;
  IF NOT InitFont() THEN
    WriteString("error: SDL_ttf init failed"); WriteLn;
    Quit;
    RETURN 1;
  END;

  (* Resolve font path *)
  IF NOT ResolveFont(fontPath) THEN
    WriteString("error: no suitable font found"); WriteLn;
    WriteString("  Place DejaVuSansMono.ttf in resources/fonts/"); WriteLn;
    WriteString("  or install a monospace font package (e.g. fonts-dejavu-core)"); WriteLn;
    QuitFont; Quit;
    RETURN 1;
  END;

  (* Open font at default logical size *)
  minPhys := LogicalMin * DpiScale();
  maxPhys := LogicalMax * DpiScale();
  physSize := minPhys + 2;
  font := OpenPhysical(fontPath, physSize);
  IF font = NIL THEN
    WriteString("error: failed to open font "); WriteString(fontPath); WriteLn;
    QuitFont; Quit;
    RETURN 1;
  END;
  SetHinting(font, HINT_MONO);

  (* Create window *)
  win := CreateWindow("hexed", InitWidth, InitHeight, WIN_CENTERED + WIN_RESIZABLE + WIN_HIGHDPI);
  IF win = NIL THEN
    WriteString("error: failed to create window"); WriteLn;
    FontClose(font); QuitFont; Quit;
    RETURN 1;
  END;

  ren := CreateRenderer(win, RENDER_ACCELERATED + RENDER_VSYNC);
  IF ren = NIL THEN
    WriteString("error: failed to create renderer"); WriteLn;
    DestroyWindow(win); FontClose(font); QuitFont; Quit;
    RETURN 1;
  END;

  (* Initialize theme *)
  ThemeInit;

  (* Open document *)
  IF NOT DocOpen(doc, path) THEN
    WriteString("error: cannot open file: "); WriteString(path); WriteLn;
    DestroyRenderer(ren); DestroyWindow(win);
    FontClose(font); QuitFont; Quit;
    RETURN 1;
  END;

  (* Set window title *)
  BuildTitle(titleBuf, doc.fileName);
  SetTitle(win, titleBuf);

  (* Initialize view *)
  ViewInit(view, font, InitWidth, InitHeight);
  MinWindowSize(view, mwW, mwH);
  SetWindowMinSize(win, mwW, mwH);

  (* Enable text input for ASCII editing *)
  StartTextInput;

  (* Main loop *)
  running := TRUE;
  needRedraw := TRUE;
  wasDirty := FALSE;
  zoomDir := 0;
  zoomHeld := FALSE;

  WHILE running DO
    (* Process all pending events *)
    evType := Poll();
    WHILE evType # NONE DO
      IF evType = WINDOW_EVENT THEN
        IF (WindowEvent() = WEVT_RESIZED) OR (WindowEvent() = WEVT_EXPOSED) THEN
          UpdateLogicalSize(ren, win);
          winW := GetWindowWidth(win);
          winH := GetWindowHeight(win);
          Resize(view, winW, winH);
          needRedraw := TRUE;
        END;
      END;
      act := HandleEvent(evType, doc, view);
      IF act = ActQuit THEN running := FALSE; END;
      IF act = ActRedraw THEN needRedraw := TRUE; END;
      IF act = ActZoomIn THEN zoomDir := 1; END;
      IF act = ActZoomOut THEN zoomDir := -1; END;
      evType := Poll();
    END;

    (* Apply zoom — one step per keypress, debounced *)
    IF zoomDir # 0 THEN
      IF NOT zoomHeld THEN
        IF (zoomDir > 0) AND (physSize < maxPhys) THEN
          INC(physSize);
          newFont := OpenPhysical(fontPath, physSize);
          IF newFont # NIL THEN
            FontClose(font); font := newFont;
            SetHinting(font, HINT_MONO);
            winW := GetWindowWidth(win); winH := GetWindowHeight(win);
            ViewInit(view, font, winW, winH);
            MinWindowSize(view, mwW, mwH);
            SetWindowMinSize(win, mwW, mwH);
            needRedraw := TRUE;
          ELSE
            DEC(physSize);
          END;
        END;
        IF (zoomDir < 0) AND (physSize > minPhys) THEN
          DEC(physSize);
          newFont := OpenPhysical(fontPath, physSize);
          IF newFont # NIL THEN
            FontClose(font); font := newFont;
            SetHinting(font, HINT_MONO);
            winW := GetWindowWidth(win); winH := GetWindowHeight(win);
            ViewInit(view, font, winW, winH);
            MinWindowSize(view, mwW, mwH);
            SetWindowMinSize(win, mwW, mwH);
            needRedraw := TRUE;
          ELSE
            INC(physSize);
          END;
        END;
        zoomHeld := TRUE;
      END;
    ELSE
      zoomHeld := FALSE;
    END;
    zoomDir := 0;

    (* Render if needed *)
    IF needRedraw THEN
      Render(view, ren, doc);
      Present(ren);
      needRedraw := FALSE;
      (* Update title bar on dirty state change *)
      IF IsDirty(doc) # wasDirty THEN
        wasDirty := IsDirty(doc);
        IF wasDirty THEN
          BuildDirtyTitle(titleBuf, doc.fileName);
        ELSE
          BuildTitle(titleBuf, doc.fileName);
        END;
        SetTitle(win, titleBuf);
      END;
    ELSE
      (* Idle — wait for events to avoid busy loop *)
      evType := WaitTimeout(16);
      IF evType # NONE THEN
        IF evType = WINDOW_EVENT THEN
          IF (WindowEvent() = WEVT_RESIZED) OR (WindowEvent() = WEVT_EXPOSED) THEN
            UpdateLogicalSize(ren, win);
            winW := GetWindowWidth(win);
            winH := GetWindowHeight(win);
            Resize(view, winW, winH);
          END;
        END;
        act := HandleEvent(evType, doc, view);
        IF act = ActQuit THEN running := FALSE; END;
        IF act = ActRedraw THEN needRedraw := TRUE; END;
        IF act = ActZoomIn THEN zoomDir := 1; END;
        IF act = ActZoomOut THEN zoomDir := -1; END;
      END;
    END;
  END;

  (* Cleanup *)
  DocClose(doc);
  DestroyRenderer(ren);
  DestroyWindow(win);
  FontClose(font);
  QuitFont;
  Quit;

  RETURN 0;
END Run;

PROCEDURE BuildDirtyTitle(VAR buf: ARRAY OF CHAR; name: ARRAY OF CHAR);
VAR i, pos: INTEGER;
BEGIN
  pos := 0;
  buf[0] := "h"; buf[1] := "e"; buf[2] := "x"; buf[3] := "e"; buf[4] := "d";
  buf[5] := " "; buf[6] := "-"; buf[7] := " ";
  pos := 8;
  i := 0;
  WHILE (i <= INTEGER(HIGH(name))) AND (name[i] # 0C) AND (pos < INTEGER(HIGH(buf)) - 12) DO
    buf[pos] := name[i];
    INC(pos);
    INC(i);
  END;
  buf[pos] := " "; INC(pos);
  buf[pos] := "["; INC(pos);
  buf[pos] := "m"; INC(pos);
  buf[pos] := "o"; INC(pos);
  buf[pos] := "d"; INC(pos);
  buf[pos] := "i"; INC(pos);
  buf[pos] := "f"; INC(pos);
  buf[pos] := "i"; INC(pos);
  buf[pos] := "e"; INC(pos);
  buf[pos] := "d"; INC(pos);
  buf[pos] := "]"; INC(pos);
  IF pos <= INTEGER(HIGH(buf)) THEN buf[pos] := 0C; END;
END BuildDirtyTitle;

PROCEDURE BuildTitle(VAR buf: ARRAY OF CHAR; name: ARRAY OF CHAR);
VAR i, pos: INTEGER;
BEGIN
  pos := 0;
  (* "hexed — " *)
  buf[0] := "h"; buf[1] := "e"; buf[2] := "x"; buf[3] := "e"; buf[4] := "d";
  buf[5] := " "; buf[6] := "-"; buf[7] := " ";
  pos := 8;
  i := 0;
  WHILE (i <= INTEGER(HIGH(name))) AND (name[i] # 0C) AND (pos < INTEGER(HIGH(buf))) DO
    buf[pos] := name[i];
    INC(pos);
    INC(i);
  END;
  IF pos <= INTEGER(HIGH(buf)) THEN buf[pos] := 0C; END;
END BuildTitle;

END App.
