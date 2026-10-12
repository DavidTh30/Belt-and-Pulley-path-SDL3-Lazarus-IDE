unit Gfx;

{ เครื่องมือวาดพื้นฐานบน SDL_Renderer: สี, เส้น, สามเหลี่ยม, วงโค้ง, สี่เหลี่ยมมุมมน, ป้าย pill }

{$mode objfpc}{$H+}

interface

uses
  SDL3;

type
  TPt = record
    x, y: Single;
  end;

  TPtArr = array of TPt;

  TRgb = record
    r, g, b: Byte;
  end;

  { ธีมสี: สีเทาทั้งหมดของ UI ไล่ระหว่าง paper (พื้น) กับ ink (ตัวหนังสือ/เส้น)
    และสีส้มที่ใช้เน้นจะเปลี่ยนเป็น accent ของธีม }
  TTheme = record
    name: string;
    paper, ink, accent: TRgb;
  end;

const
  THEMES: array[0..11] of TTheme = (
    (name: 'Paper';           paper: (r: 252; g: 252; b: 250); ink: (r: 22;  g: 22;  b: 22);  accent: (r: 220; g: 90;  b: 20)),
    (name: 'Dark';            paper: (r: 30;  g: 32;  b: 36);  ink: (r: 226; g: 226; b: 222); accent: (r: 255; g: 145; b: 60)),
    (name: 'Blueprint';       paper: (r: 20;  g: 60;  b: 115); ink: (r: 232; g: 242; b: 255); accent: (r: 255; g: 212; b: 80)),
    (name: 'Sepia';           paper: (r: 244; g: 234; b: 214); ink: (r: 72;  g: 50;  b: 30);  accent: (r: 190; g: 80;  b: 40)),
    (name: 'Solarized Light'; paper: (r: 253; g: 246; b: 227); ink: (r: 7;   g: 54;  b: 66);  accent: (r: 203; g: 75;  b: 22)),
    (name: 'Solarized Dark';  paper: (r: 0;   g: 43;  b: 54);  ink: (r: 238; g: 232; b: 213); accent: (r: 181; g: 137; b: 0)),
    (name: 'Terminal';        paper: (r: 8;   g: 16;  b: 10);  ink: (r: 95;  g: 255; b: 130); accent: (r: 255; g: 200; b: 0)),
    (name: 'Midnight';        paper: (r: 26;  g: 22;  b: 46);  ink: (r: 222; g: 212; b: 255); accent: (r: 255; g: 110; b: 200)),
    (name: 'Mint';            paper: (r: 236; g: 248; b: 242); ink: (r: 18;  g: 72;  b: 62);  accent: (r: 0;   g: 150; b: 120)),
    (name: 'High Contrast';   paper: (r: 0;   g: 0;   b: 0);   ink: (r: 255; g: 255; b: 255); accent: (r: 255; g: 255; b: 0)),
    (name: 'Nord';            paper: (r: 46;  g: 52;  b: 64);  ink: (r: 236; g: 239; b: 244); accent: (r: 136; g: 192; b: 208)),
    (name: 'Rose';            paper: (r: 255; g: 240; b: 244); ink: (r: 92;  g: 30;  b: 52);  accent: (r: 220; g: 60;  b: 110)));

var
  ThemeIdx: Integer = 0;

var
  Ren: PSDL_Renderer;

function Pt(x, y: Single): TPt;
procedure SetTheme(i: Integer);
function FindTheme(const name: string): Integer;
{ สีของ UI: ผ่านธีม }
procedure Col(r, g, b: Byte);
{ สีตามจริง (สีที่ผู้ใช้เลือก: สีทา, ตัวอย่างสี) }
procedure ColRaw(r, g, b: Byte);
{ สีของเอกสาร: ถ้ายังเป็นค่าตั้งต้นให้ตามธีม ถ้าผู้ใช้ตั้งเองใช้ตามจริง }
procedure ColDoc(const c, def: TRgb);
procedure Ink;
procedure Paper;
procedure Tri(x1, y1, x2, y2, x3, y3: Single);
procedure Quad(const a, b, c, d: TPt);
procedure Flush;
procedure Txt(x, y: Single; const s: string);
procedure Line(x1, y1, x2, y2: Single);
procedure ThickLine(x1, y1, x2, y2, w: Single);
procedure Disc(cx, cy, r: Single);
procedure ArcBand(cx, cy, r1, r2, a0, a1: Single);
procedure ArcLine(cx, cy, r, a0, a1: Single);
procedure FillRect(x, y, w, h: Single);
procedure StrokeRect(x, y, w, h: Single);
procedure FillRoundRect(x, y, w, h, rad: Single);
procedure StrokeRoundRect(x, y, w, h, rad: Single);
function Pill(x, y: Single; const s: string; filled: Boolean): Single;
procedure DashedCircle(cx, cy, r: Single);
procedure DashedLine(x1, y1, x2, y2: Single);
procedure Panel(x, y, w, h: Single);
procedure SetClip(x, y, w, h: Integer);

implementation

uses
  SysUtils, Math;

var
  Verts: array of TSDL_Vertex;
  VertN: Integer = 0;
  CurCol: TSDL_FColor;

procedure SetTheme(i: Integer);
begin
  ThemeIdx := EnsureRange(i, 0, High(THEMES));
end;

function FindTheme(const name: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(THEMES) do
    if SameText(THEMES[i].name, name) then Exit(i);
end;

procedure Col(r, g, b: Byte);
var
  t: Single;
  th: TTheme;
begin
  th := THEMES[ThemeIdx];
  if (r = 220) and (g = 90) and (b = 20) then
  begin
    ColRaw(th.accent.r, th.accent.g, th.accent.b);
    Exit;
  end;
  if MaxValue([Integer(r), g, b]) - MinValue([Integer(r), g, b]) <= 24 then
  begin
    { สีเทา: 22 = ink, 252 = paper, ระหว่างนั้นไล่สี }
    t := EnsureRange(((r + g + b) / 3 - 22) / 230, 0, 1);
    ColRaw(Round(th.ink.r + (th.paper.r - th.ink.r) * t),
           Round(th.ink.g + (th.paper.g - th.ink.g) * t),
           Round(th.ink.b + (th.paper.b - th.ink.b) * t));
    Exit;
  end;
  ColRaw(r, g, b);
end;

procedure ColDoc(const c, def: TRgb);
begin
  if (c.r = def.r) and (c.g = def.g) and (c.b = def.b) then
    Col(c.r, c.g, c.b)
  else
    ColRaw(c.r, c.g, c.b);
end;

function Pt(x, y: Single): TPt;
begin
  Result.x := x;
  Result.y := y;
end;

procedure FillRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderFillRect(Ren, @rc);
end;

procedure StrokeRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderRect(Ren, @rc);
end;

procedure ColRaw(r, g, b: Byte);
begin
  SDL_SetRenderDrawColor(Ren, r, g, b, 255);
  CurCol.r := r / 255;
  CurCol.g := g / 255;
  CurCol.b := b / 255;
  CurCol.a := 1;
end;

procedure Ink;   begin Col(22, 22, 22); end;
procedure Paper; begin Col(252, 252, 250); end;

procedure AddV(x, y: Single);
begin
  if VertN >= Length(Verts) then
    SetLength(Verts, VertN * 2 + 256);
  Verts[VertN].position.x := x;
  Verts[VertN].position.y := y;
  Verts[VertN].color := CurCol;
  Verts[VertN].tex_coord.x := 0;
  Verts[VertN].tex_coord.y := 0;
  Inc(VertN);
end;

procedure Tri(x1, y1, x2, y2, x3, y3: Single);
begin
  AddV(x1, y1); AddV(x2, y2); AddV(x3, y3);
end;

procedure Quad(const a, b, c, d: TPt);   // a-b ขอบหนึ่ง, d-c อีกขอบ
begin
  Tri(a.x, a.y, b.x, b.y, c.x, c.y);
  Tri(a.x, a.y, c.x, c.y, d.x, d.y);
end;

procedure Flush;
begin
  if VertN > 0 then
    SDL_RenderGeometry(Ren, nil, @Verts[0], VertN, nil, 0);
  VertN := 0;
end;

procedure Txt(x, y: Single; const s: string);
begin
  SDL_RenderDebugText(Ren, x, y, PAnsiChar(s));
end;

procedure Line(x1, y1, x2, y2: Single);
begin
  SDL_RenderLine(Ren, x1, y1, x2, y2);
end;

procedure ThickLine(x1, y1, x2, y2, w: Single);
var
  dx, dy, L: Single;
begin
  dx := x2 - x1; dy := y2 - y1;
  L := Hypot(dx, dy);
  if L < 1e-4 then Exit;
  dx := -dy / L * w / 2;
  dy := (x2 - x1) / L * w / 2;
  Quad(Pt(x1 + dx, y1 + dy), Pt(x2 + dx, y2 + dy), Pt(x2 - dx, y2 - dy), Pt(x1 - dx, y1 - dy));
  Flush;
end;

procedure Disc(cx, cy, r: Single);
var
  k, n: Integer;
  a0, a1: Single;
begin
  n := Max(10, Round(r * 3));
  for k := 0 to n - 1 do
  begin
    a0 := 2 * Pi * k / n;
    a1 := 2 * Pi * (k + 1) / n;
    Tri(cx, cy, cx + r * Cos(a0), cy + r * Sin(a0), cx + r * Cos(a1), cy + r * Sin(a1));
  end;
  Flush;
end;

{ แถบโค้งหนาระหว่างรัศมี r1..r2 จากมุม a0 ถึง a1 }
procedure ArcBand(cx, cy, r1, r2, a0, a1: Single);
var
  k, n: Integer;
  b0, b1: Single;
begin
  n := Max(2, Ceil(Abs(a1 - a0) * r2 / 2.5));
  for k := 0 to n - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n;
    b1 := a0 + (a1 - a0) * (k + 1) / n;
    Quad(Pt(cx + r1 * Cos(b0), cy + r1 * Sin(b0)), Pt(cx + r1 * Cos(b1), cy + r1 * Sin(b1)),
         Pt(cx + r2 * Cos(b1), cy + r2 * Sin(b1)), Pt(cx + r2 * Cos(b0), cy + r2 * Sin(b0)));
  end;
  Flush;
end;

procedure ArcLine(cx, cy, r, a0, a1: Single);
var
  k, n: Integer;
  b0, b1: Single;
begin
  n := Max(2, Ceil(Abs(a1 - a0) * r / 3));
  for k := 0 to n - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n;
    b1 := a0 + (a1 - a0) * (k + 1) / n;
    Line(cx + r * Cos(b0), cy + r * Sin(b0), cx + r * Cos(b1), cy + r * Sin(b1));
  end;
end;

procedure RoundRectPts(x, y, w, h, rad: Single; out P: TPtArr);
const
  SEG = 5;
var
  k, c, n: Integer;
  cx, cy, a: Single;
begin
  SetLength(P, 4 * (SEG + 1));
  n := 0;
  for c := 0 to 3 do
  begin
    case c of
      0: begin cx := x + w - rad; cy := y + rad; end;
      1: begin cx := x + w - rad; cy := y + h - rad; end;
      2: begin cx := x + rad;     cy := y + h - rad; end;
    else begin cx := x + rad;     cy := y + rad; end;
    end;
    for k := 0 to SEG do
    begin
      a := -Pi / 2 + (c + k / SEG) * Pi / 2;
      P[n] := Pt(cx + rad * Cos(a), cy + rad * Sin(a));
      Inc(n);
    end;
  end;
end;

procedure FillRoundRect(x, y, w, h, rad: Single);
var
  P: TPtArr;
  i, j: Integer;
begin
  RoundRectPts(x, y, w, h, rad, P);
  for i := 0 to High(P) do
  begin
    j := (i + 1) mod Length(P);
    Tri(x + w / 2, y + h / 2, P[i].x, P[i].y, P[j].x, P[j].y);
  end;
  Flush;
end;

procedure StrokeRoundRect(x, y, w, h, rad: Single);
var
  P: TPtArr;
  i, j: Integer;
begin
  RoundRectPts(x, y, w, h, rad, P);
  for i := 0 to High(P) do
  begin
    j := (i + 1) mod Length(P);
    Line(P[i].x, P[i].y, P[j].x, P[j].y);
  end;
end;

{ ป้ายแบบ pill: ทึบ = พื้นดำตัวขาว, โปร่ง = กรอบดำ; คืนค่าความกว้าง }
function Pill(x, y: Single; const s: string; filled: Boolean): Single;
begin
  Result := Length(s) * 8 + 12;
  Ink;
  if filled then
  begin
    FillRoundRect(x, y, Result, 15, 6);
    Paper;
  end
  else
  begin
    Paper;
    FillRoundRect(x, y, Result, 15, 6);
    Ink;
    StrokeRoundRect(x, y, Result, 15, 6);
  end;
  Txt(x + 6, y + 4, s);
end;

procedure DashedCircle(cx, cy, r: Single);
var
  k, segs: Integer;
begin
  segs := Max(16, Round(r * 2 * Pi / 7));
  if Odd(segs) then Inc(segs);
  for k := 0 to segs - 1 do
    if not Odd(k) then
      ArcLine(cx, cy, r, 2 * Pi * k / segs, 2 * Pi * (k + 1) / segs);
end;

procedure DashedLine(x1, y1, x2, y2: Single);
var
  L, t0, t1: Single;
  k, n: Integer;
begin
  L := Hypot(x2 - x1, y2 - y1);
  n := Max(1, Round(L / 4));
  for k := 0 to n - 1 do
    if not Odd(k) then
    begin
      t0 := k / n; t1 := (k + 1) / n;
      Line(x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1);
    end;
end;

procedure Panel(x, y, w, h: Single);
begin
  Paper;
  FillRoundRect(x, y, w, h, 7);
  Col(70, 70, 70);
  StrokeRoundRect(x, y, w, h, 7);
end;

procedure SetClip(x, y, w, h: Integer);
var
  rc: TSDL_Rect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_SetRenderClipRect(Ren, @rc);
end;

end.
