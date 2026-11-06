unit FleetTheme;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Types,Graphics,Controls,ExtCtrls,Forms,LCLType;
const ThemeBackground=$00F7F5F2; ThemeInk=$00382C22; ThemeBlue=$00D77812;
type
  TFleetIconKind=(fiNone,fiLayers,fiCalendar,fiTemperature,fiHumidity,fiLock,fiDocument,fiLink,fiWarning,fiChevron);
  TFleetIcon=class(TGraphicControl)
  private FKind: TFleetIconKind; FInk: TColor;
    procedure SetKind(Value: TFleetIconKind);
    procedure SetInk(Value: TColor);
  protected procedure Paint; override;
  public constructor Create(AOwner:TComponent); override;
    property Kind:TFleetIconKind read FKind write SetKind;
    property Ink:TColor read FInk write SetInk;
  end;
  TThemeCard=class(TPanel)
  private FFill:TColor; FHeading:Integer;
    procedure SetFill(Value:TColor);
  protected procedure Paint; override;
  public constructor Create(AOwner:TComponent); override;
    property FillColor:TColor read FFill write SetFill;
    property HeadingHeight:Integer read FHeading write FHeading;
  end;
  TThemeButton=class(TCustomControl)
  private FPrimary,FHover,FPressed,FDropDown:Boolean; FIcon:TFleetIconKind; FModal:TModalResult; FDefault,FCancel:Boolean;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override;
    procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override;
    procedure KeyDown(var Key:Word;Shift:TShiftState); override;
  public
    constructor Create(AOwner:TComponent); override;
    procedure Click; override;
    property Primary:Boolean read FPrimary write FPrimary;
    property DropDown:Boolean read FDropDown write FDropDown;
    property Icon:TFleetIconKind read FIcon write FIcon;
    property ModalResult:TModalResult read FModal write FModal;
    property Default:Boolean read FDefault write FDefault;
    property Cancel:Boolean read FCancel write FCancel;
  published property Caption; property OnClick; property TabStop; property TabOrder;
  end;
procedure DrawFleetIcon(C:TCanvas;Kind:TFleetIconKind;const R:TRect;Ink:TColor);
implementation
procedure DrawFleetIcon(C:TCanvas;Kind:TFleetIconKind;const R:TRect;Ink:TColor);
var W:Integer;
  function P(X,Y:Integer):TPoint;begin Result:=Point(R.Left+X*(R.Right-R.Left) div 24,R.Top+Y*(R.Bottom-R.Top) div 24) end;
  procedure Line(X1,Y1,X2,Y2:Integer);var A,B:TPoint;begin A:=P(X1,Y1);B:=P(X2,Y2);C.Line(A.X,A.Y,B.X,B.Y) end;
  procedure Box(X1,Y1,X2,Y2:Integer);var A,B:TPoint;begin A:=P(X1,Y1);B:=P(X2,Y2);C.RoundRect(A.X,A.Y,B.X,B.Y,4,4) end;
begin
  W:=R.Right-R.Left; C.Pen.Color:=Ink; C.Pen.Width:=W div 14;if C.Pen.Width<1 then C.Pen.Width:=1;C.Brush.Style:=bsClear;
  case Kind of
    fiLayers:begin C.Polyline([P(2,8),P(12,3),P(22,8),P(12,13),P(2,8)]);C.Polyline([P(2,13),P(12,18),P(22,13)]);C.Polyline([P(2,18),P(12,23),P(22,18)]) end;
    fiCalendar:begin Box(3,5,22,22);Line(3,10,22,10);Line(8,2,8,8);Line(17,2,17,8);Line(8,14,11,14);Line(15,14,18,14);Line(8,18,11,18) end;
    fiTemperature:begin Box(9,2,15,18);C.Ellipse(P(7,14).X,P(7,14).Y,P(17,24).X,P(17,24).Y);Line(12,8,12,20);Line(18,7,22,7);Line(18,11,21,11) end;
    fiHumidity:C.Polyline([P(12,2),P(5,12),P(3,17),P(5,21),P(9,23),P(15,23),P(20,20),P(21,16),P(18,10),P(12,2)]);
    fiLock:begin Box(7,1,17,14);Box(3,10,21,23);Line(12,15,12,19) end;
    fiDocument:begin Box(4,2,20,23);Line(8,7,15,7);Line(8,12,16,12);Line(8,17,16,17) end;
    fiLink:begin Box(1,10,14,23);Box(10,1,23,14);Line(8,16,17,7) end;
    fiChevron:C.Polyline([P(5,9),P(12,16),P(19,9)]);
    fiWarning:begin
      C.Brush.Style:=bsSolid;C.Brush.Color:=Ink;C.Polygon([P(12,1),P(1,22),P(23,22)]);
      C.Pen.Color:=clWhite;C.Pen.Width:=W div 10;if C.Pen.Width<2 then C.Pen.Width:=2;Line(12,8,12,14);Line(12,17,12,18);
    end;
  end;
  C.Pen.Width:=1;C.Brush.Style:=bsSolid;
end;
constructor TFleetIcon.Create(AOwner:TComponent);begin inherited Create(AOwner);Width:=28;Height:=28;FInk:=ThemeBlue end;
procedure TFleetIcon.SetKind(Value:TFleetIconKind);begin if FKind<>Value then begin FKind:=Value;Invalidate end end;
procedure TFleetIcon.SetInk(Value:TColor);begin if FInk<>Value then begin FInk:=Value;Invalidate end end;
procedure TFleetIcon.Paint;begin DrawFleetIcon(Canvas,FKind,ClientRect,FInk) end;
constructor TThemeCard.Create(AOwner:TComponent);begin inherited Create(AOwner);BevelOuter:=bvNone;ParentBackground:=False;Color:=ThemeBackground;FFill:=clWhite;Caption:='';DoubleBuffered:=True end;
procedure TThemeCard.SetFill(Value:TColor);begin if FFill<>Value then begin FFill:=Value;Invalidate end end;
procedure TThemeCard.Paint;
var H,R:Integer;
begin
  Canvas.Brush.Color:=ThemeBackground;Canvas.FillRect(ClientRect);R:=Scale96ToForm(10);
  Canvas.Brush.Color:=$00E5E0DA;Canvas.Pen.Color:=$00E5E0DA;Canvas.RoundRect(0,2,Width,Height,R,R);
  Canvas.Brush.Color:=FFill;Canvas.Pen.Color:=$00D4C9BE;Canvas.RoundRect(0,0,Width-1,Height-2,R,R);
  H:=Scale96ToForm(FHeading);
  if H>0 then begin
    Canvas.Pen.Style:=psClear;Canvas.Brush.Color:=$00F4EFE9;
    Canvas.RoundRect(1,1,Width-2,H,R,R);Canvas.FillRect(Rect(1,H-R,Width-2,H));
    Canvas.Pen.Style:=psSolid;Canvas.Pen.Color:=$00D4C9BE;Canvas.Line(1,H,Width-2,H);
  end;
end;
constructor TThemeButton.Create(AOwner:TComponent);
begin inherited Create(AOwner);ControlStyle:=ControlStyle-[csClickEvents];Width:=150;Height:=38;TabStop:=True;Cursor:=crHandPoint;DoubleBuffered:=True;Font.Name:='Segoe UI';Font.Size:=10 end;
procedure TThemeButton.Paint;
var Fill,Ink,Border:TColor;X,Y,Gap,Size:Integer;R:TRect;
begin
  Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);
  Fill:=$00F8F5F1;Ink:=ThemeInk;Border:=$00C4B5A5;
  if FHover then begin Fill:=$00FFF4E6;Border:=ThemeBlue end;
  if FPressed then Fill:=$00F2E5D4;
  if FPrimary then begin Fill:=ThemeBlue;Ink:=clWhite;Border:=ThemeBlue;if FHover then Fill:=$00BD650B;if FPressed then Fill:=$00A45205 end;
  if not Enabled then begin Fill:=$00EDEDED;Ink:=clGray;Border:=clSilver end;
  Canvas.Brush.Color:=Fill;Canvas.Pen.Color:=Border;Size:=Scale96ToForm(7);Canvas.RoundRect(0,0,Width-1,Height-1,Size,Size);
  Canvas.Font.Assign(Font);Canvas.Font.Color:=Ink;Canvas.Brush.Style:=bsClear;
  Size:=Scale96ToForm(20);Gap:=0;if FIcon<>fiNone then Gap:=Size+Scale96ToForm(10);
  X:=(Width-Canvas.TextWidth(Caption)-Gap) div 2;Y:=(Height-Canvas.TextHeight(Caption)) div 2;
  if FDropDown then begin X:=Scale96ToForm(14);DrawFleetIcon(Canvas,fiChevron,Rect(Width-Size-Scale96ToForm(12),(Height-Size) div 2,Width-Scale96ToForm(12),(Height+Size) div 2),$00705B47) end;
  if FIcon<>fiNone then DrawFleetIcon(Canvas,FIcon,Rect(X,(Height-Size) div 2,X+Size,(Height+Size) div 2),Ink);
  Canvas.Brush.Style:=bsClear;Canvas.TextOut(X+Gap,Y,Caption);
  if Focused then begin R:=ClientRect;InflateRect(R,-4,-4);Canvas.DrawFocusRect(R) end;
end;
procedure TThemeButton.MouseEnter;begin inherited;FHover:=True;Invalidate end;
procedure TThemeButton.MouseLeave;begin inherited;FHover:=False;Invalidate end;
procedure TThemeButton.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
begin inherited;if (Button=mbLeft) and Enabled then begin SetFocus;FPressed:=True;MouseCapture:=True;Invalidate end end;
procedure TThemeButton.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
var Fire:Boolean;
begin Fire:=FPressed and (Button=mbLeft) and PtInRect(ClientRect,Point(X,Y));FPressed:=False;MouseCapture:=False;Invalidate;inherited;if Fire then Click end;
procedure TThemeButton.KeyDown(var Key:Word;Shift:TShiftState);
begin inherited;if (Key=VK_SPACE) or (Key=VK_RETURN) then begin Key:=0;Click end end;
procedure TThemeButton.Click;
var F:TCustomForm;
begin if not Enabled then Exit;inherited;if FModal<>mrNone then begin F:=GetParentForm(Self);if Assigned(F) then F.ModalResult:=FModal end end;
end.
