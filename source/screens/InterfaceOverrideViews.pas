{$EXCESSPRECISION OFF}
unit InterfaceOverrideViews;
{$R-}
{$Q-}
{$B-}
{$A8}

// CHANGE: CLEANUP - Scripts restyle UI controls through overrides that the galaxy saves
// (TInterface*Override in aGalaxy). These subclasses apply them to the controls; the code
// is what the overrides ran themselves before. Setting the class variables makes the
// galaxy and scripts create these.
interface
uses
  aGalaxy;
type
  TInterfaceStateOverrideView = class(TInterfaceStateOverride)
    destructor Destroy; override;
    procedure Initialize(FormName, ControlPath: WideString; State: Byte); override;
    procedure SetState(State: Byte); override;
    procedure Reapply; override;
  end;
  TInterfaceTextOverrideView = class(TInterfaceTextOverride)
    destructor Destroy; override;
    procedure Initialize(FormName, ControlPath: WideString; Text: WideString); override;
    procedure SetText(Text: WideString); override;
    procedure Reapply; override;
  end;
  TInterfaceImageOverrideView = class(TInterfaceImageOverride)
    destructor Destroy; override;
    procedure Initialize(
        FormName, ControlPath: WideString;
        ImagePath: WideString
    ); override;
    procedure SetImagePath(ImagePath: WideString); override;
    procedure Reapply; override;
  end;
  TInterfacePosOverrideView = class(TInterfacePosOverride)
    destructor Destroy; override;
    procedure Initialize(
        FormName, ControlPath: WideString;
        DeltaX, DeltaY, DeltaDepth: Integer
    ); override;
    procedure SetPosition(DeltaX, DeltaY, DeltaDepth: Integer); override;
    procedure Reapply; override;
  end;
  TInterfaceSizeOverrideView = class(TInterfaceSizeOverride)
    destructor Destroy; override;
    procedure Initialize(
        FormName, ControlPath: WideString;
        Width, Height: Integer
    ); override;
    procedure SetSize(Width, Height: Integer); override;
    procedure Reapply; override;
  end;
implementation
uses
  Classes,
  SysUtils,
  EC_Str,
  GI_GAI,
  GI_GI,
  GI_GraphButton,
  GI_Image,
  GI_Label,
  GI_MessageLoop,
  GR_Main,
  Globals;

destructor TInterfaceStateOverrideView.Destroy;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(FormName);
  if Form <> nil then
  begin
    Control := Form.FindControlByPath(ControlPath);
    if Control <> nil then
    begin
      Control.SetActive(OriginalState > 0);
      if (OriginalState > 1) and (Control is TGraphButtonGI) then
        TGraphButtonGI(Control).SetDisabled(OriginalState = 2);
    end;
  end;
  inherited Destroy;
end;
procedure TInterfaceStateOverrideView.Initialize(FormName, ControlPath: WideString; State: Byte);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.FormName := FormName;
  Self.ControlPath := ControlPath;
  Self.State := State;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceStateOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    OriginalState := Ord(Control.Active);
    Control.SetActive(Self.State > 0);
    if (OriginalState > 0) and (Control is TGraphButtonGI) then
      OriginalState := 3 - Ord(TGraphButtonGI(Control).Disabled);
    if (Self.State > 1) and (Control is TGraphButtonGI) then
      TGraphButtonGI(Control).SetDisabled(Self.State = 2);
  end;
end;
procedure TInterfaceStateOverrideView.SetState(State: Byte);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.State := State;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceStateOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    Control.SetActive(Self.State > 0);
    if (Self.State > 1) and (Control is TGraphButtonGI) then
      TGraphButtonGI(Control).SetDisabled(Self.State = 2);
  end;
end;
procedure TInterfaceStateOverrideView.Reapply;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceStateOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    Control.SetActive(Self.State > 0);
    if (Self.State > 1) and (Control is TGraphButtonGI) then
      TGraphButtonGI(Control).SetDisabled(Self.State = 2);
  end;
end;
destructor TInterfaceTextOverrideView.Destroy;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(FormName);
  if Form <> nil then
  begin
    Control := Form.FindControlByPath(ControlPath);
    if Control <> nil then
    begin
      if not (Control is TLabelGI) then
        AppendLogLineThreadSafe(AnsiString('Object is not a label - ' + ControlPath))
      else
        (Control as TLabelGI).SetText(OriginalText);
    end;
  end;
  inherited Destroy;
end;
procedure TInterfaceTextOverrideView.Initialize(FormName, ControlPath: WideString; Text: WideString);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.FormName := FormName;
  Self.ControlPath := ControlPath;
  Self.Text := Text;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceTextOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    if not (Control is TLabelGI) then
      raise Exception.Create(AnsiString('Object is not a label - ' + Self.ControlPath));
    OriginalText := (Control as TLabelGI).GetText;
    (Control as TLabelGI).SetText(Self.Text);
  end;
end;
procedure TInterfaceTextOverrideView.SetText(Text: WideString);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.Text := Text;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceTextOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    if not (Control is TLabelGI) then
      raise Exception.Create(AnsiString('Object is not a label - ' + Self.ControlPath));
    (Control as TLabelGI).SetText(Self.Text);
  end;
end;
procedure TInterfaceTextOverrideView.Reapply;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceTextOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    if not (Control is TLabelGI) then
      raise Exception.Create(AnsiString('Object is not a label - ' + Self.ControlPath));
    (Control as TLabelGI).SetText(Self.Text);
  end;
end;
destructor TInterfaceImageOverrideView.Destroy;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(FormName);
  if Form <> nil then
  begin
    Control := Form.FindControlByPath(ControlPath);
    if Control <> nil then
    begin
      if (CountDelimitedPartsW(ImagePath, ':') > 1)
          and (ExtractDelimitedPartW(ImagePath, 0, ':') = 'Style') then
      begin
        if OriginalImagePath <> '' then
          Control.SetConfigPath(OriginalImagePath);
      end
      else if Control is TgaiGI then
      begin
        // Native tests the replacement path before restoring the original.
        if CountDelimitedPartsW(ImagePath, '|') < 2 then
          TgaiGI(Control).SetImagePath(OriginalImagePath)
        else
        begin
          TgaiGI(Control).SetFirstFrameImagePath(ExtractDelimitedPartW(OriginalImagePath, 1, '|'));
          TgaiGI(Control).SetImagePath(ExtractDelimitedPartW(OriginalImagePath, 0, '|'));
        end;
        TgaiGI(Control).PrimeImageCaches;
        TgaiGI(Control).SequenceIndex := 0;
        TgaiGI(Control).UpdateAutoGeometry;
        TgaiGI(Control).RestartPlayback;
      end
      else if Control is TgiGI then
        (Control as TgiGI).SetImagePath(OriginalImagePath)
      else if Control is TImageGI then
        (Control as TImageGI).SetImagePath(OriginalImagePath)
      else
        AppendLogLineThreadSafe(AnsiString('Object is not an image - ' + ControlPath));
    end;
  end;
  inherited Destroy;
end;
procedure TInterfaceImageOverrideView.Initialize(
    FormName, ControlPath: WideString;
    ImagePath: WideString
);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.FormName := FormName;
  Self.ControlPath := ControlPath;
  Self.ImagePath := ImagePath;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceImageOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
                + ' ('
                + Self.ImagePath
                + ')'
        )
    )
  else
  begin
    if (CountDelimitedPartsW(Self.ImagePath, ':') > 1)
        and (ExtractDelimitedPartW(Self.ImagePath, 0, ':') = 'Style') then
    begin
      OriginalImagePath := Control.ConfigPath;
      Control.SetConfigPath(ExtractDelimitedPartW(Self.ImagePath, 1, ':'));
    end
    else if Control is TgaiGI then
    begin
      OriginalImagePath := TgaiGI(Control).GetImagePath;
      if TgaiGI(Control).GetFirstFrameImagePath <> '' then
        OriginalImagePath := OriginalImagePath + '|' + TgaiGI(Control).GetFirstFrameImagePath;
      if CountDelimitedPartsW(Self.ImagePath, '|') < 2 then
        TgaiGI(Control).SetImagePath(Self.ImagePath)
      else
      begin
        TgaiGI(Control).SetFirstFrameImagePath(ExtractDelimitedPartW(Self.ImagePath, 1, '|'));
        TgaiGI(Control).SetImagePath(ExtractDelimitedPartW(Self.ImagePath, 0, '|'));
      end;
      TgaiGI(Control).PrimeImageCaches;
      TgaiGI(Control).SequenceIndex := 0;
      TgaiGI(Control).UpdateAutoGeometry;
      TgaiGI(Control).RestartPlayback;
    end
    else if Control is TgiGI then
    begin
      OriginalImagePath := (Control as TgiGI).GetImagePath;
      (Control as TgiGI).SetImagePath(Self.ImagePath);
    end
    else if Control is TImageGI then
    begin
      OriginalImagePath := (Control as TImageGI).GetImagePath;
      (Control as TImageGI).SetImagePath(Self.ImagePath);
    end
    else
      raise Exception.Create(AnsiString('Object is not an image - ' + Self.ControlPath));
  end;
end;
procedure TInterfaceImageOverrideView.SetImagePath(ImagePath: WideString);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.ImagePath := ImagePath;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceImageOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
                + ' ('
                + Self.ImagePath
                + ')'
        )
    )
  else
  begin
    if (CountDelimitedPartsW(Self.ImagePath, ':') > 1)
        and (ExtractDelimitedPartW(Self.ImagePath, 0, ':') = 'Style') then
    begin
      Control.SetConfigPath(ExtractDelimitedPartW(Self.ImagePath, 1, ':'));
    end
    else if Control is TgaiGI then
    begin
      if CountDelimitedPartsW(Self.ImagePath, '|') < 2 then
        TgaiGI(Control).SetImagePath(Self.ImagePath)
      else
      begin
        TgaiGI(Control).SetFirstFrameImagePath(ExtractDelimitedPartW(OriginalImagePath, 1, '|'));
        TgaiGI(Control).SetImagePath(ExtractDelimitedPartW(OriginalImagePath, 0, '|'));
      end;
      TgaiGI(Control).PrimeImageCaches;
      TgaiGI(Control).SequenceIndex := 0;
      TgaiGI(Control).UpdateAutoGeometry;
      TgaiGI(Control).RestartPlayback;
    end
    else if Control is TgiGI then
    begin
      (Control as TgiGI).SetImagePath(Self.ImagePath);
    end
    else if Control is TImageGI then
    begin
      (Control as TImageGI).SetImagePath(Self.ImagePath);
    end
    else
      raise Exception.Create(AnsiString('Object is not an image - ' + Self.ControlPath));
  end;
end;
procedure TInterfaceImageOverrideView.Reapply;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceImageOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
                + ' ('
                + Self.ImagePath
                + ')'
        )
    )
  else
  begin
    if (CountDelimitedPartsW(Self.ImagePath, ':') > 1)
        and (ExtractDelimitedPartW(Self.ImagePath, 0, ':') = 'Style') then
    begin
      Control.SetConfigPath(ExtractDelimitedPartW(Self.ImagePath, 1, ':'));
    end
    else if Control is TgaiGI then
    begin
      if CountDelimitedPartsW(Self.ImagePath, '|') < 2 then
        TgaiGI(Control).SetImagePath(Self.ImagePath)
      else
      begin
        TgaiGI(Control).SetFirstFrameImagePath(ExtractDelimitedPartW(Self.ImagePath, 1, '|'));
        TgaiGI(Control).SetImagePath(ExtractDelimitedPartW(Self.ImagePath, 0, '|'));
      end;
      TgaiGI(Control).PrimeImageCaches;
      TgaiGI(Control).SequenceIndex := 0;
      TgaiGI(Control).UpdateAutoGeometry;
      TgaiGI(Control).RestartPlayback;
    end
    else if Control is TgiGI then
    begin
      (Control as TgiGI).SetImagePath(Self.ImagePath);
    end
    else if Control is TImageGI then
    begin
      (Control as TImageGI).SetImagePath(Self.ImagePath);
    end
    else
      raise Exception.Create(AnsiString('Object is not an image - ' + Self.ControlPath));
  end;
end;
destructor TInterfacePosOverrideView.Destroy;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(FormName);
  if Form <> nil then
  begin
    Control := Form.FindControlByPath(ControlPath);
    if Control <> nil then
    begin
      Control.SetPosition(Classes.Point(OriginalPosition.X, OriginalPosition.Y));
      Control.SetDepth(OriginalDepth);
    end;
  end;
  inherited Destroy;
end;
procedure TInterfacePosOverrideView.Initialize(
    FormName, ControlPath: WideString;
    DeltaX, DeltaY, DeltaDepth: Integer
);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.FormName := FormName;
  Self.ControlPath := ControlPath;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfacePosOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    OriginalPosition.X := Control.LocalPosition.X;
    OriginalPosition.Y := Control.LocalPosition.Y;
    OriginalDepth := Control.Depth;
    Position.X := DeltaX + OriginalPosition.X;
    Position.Y := DeltaY + OriginalPosition.Y;
    Depth := OriginalDepth + DeltaDepth;
    Control.SetPosition(Classes.Point(Position.X, Position.Y));
    Control.SetDepth(Depth);
  end;
end;
procedure TInterfacePosOverrideView.SetPosition(DeltaX, DeltaY, DeltaDepth: Integer);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfacePosOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    Position.X := DeltaX + OriginalPosition.X;
    Position.Y := DeltaY + OriginalPosition.Y;
    Depth := OriginalDepth + DeltaDepth;
    Control.SetPosition(Classes.Point(Position.X, Position.Y));
    Control.SetDepth(Depth);
  end;
end;
procedure TInterfacePosOverrideView.Reapply;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfacePosOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    Control.SetPosition(Classes.Point(Position.X, Position.Y));
    Control.SetDepth(Depth);
  end;
end;
destructor TInterfaceSizeOverrideView.Destroy;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(FormName);
  if Form <> nil then
  begin
    Control := Form.FindControlByPath(ControlPath);
    if Control <> nil then
    begin
      Control.SetSize(Classes.Point(OriginalSize.X, OriginalSize.Y));
    end;
  end;
  inherited Destroy;
end;
procedure TInterfaceSizeOverrideView.Initialize(
    FormName, ControlPath: WideString;
    Width, Height: Integer
);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Self.FormName := FormName;
  Self.ControlPath := ControlPath;
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceSizeOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    OriginalSize.X := Control.ClientSize.X;
    OriginalSize.Y := Control.ClientSize.Y;
    if Width > 0 then
      Size.X := Width
    else
      Size.X := OriginalSize.X;
    if Height > 0 then
      Size.Y := Height
    else
      Size.Y := OriginalSize.Y;
    Control.SetSize(Classes.Point(Size.X, Size.Y));
  end;
end;
procedure TInterfaceSizeOverrideView.SetSize(Width, Height: Integer);
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceSizeOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    if Width > 0 then
      Size.X := Width
    else
      Size.X := OriginalSize.X;
    if Height > 0 then
      Size.Y := Height
    else
      Size.Y := OriginalSize.Y;
    Control.SetSize(Classes.Point(Size.X, Size.Y));
  end;
end;
procedure TInterfaceSizeOverrideView.Reapply;
var
  Form: TMessageLoopGI;
  Control: TObjectGI;
begin
  Form := FindMessageLoop(Self.FormName);
  if Form = nil then
    raise Exception.Create(AnsiString('ML not found - ' + Self.FormName));
  Control := Form.FindControlByPath(Self.ControlPath);
  if Control = nil then
    AppendLogLineThreadSafe(
        AnsiString(
            'TInterfaceSizeOverride: object not found - '
                + Self.ControlPath
                + ' on form '
                + Self.FormName
        )
    )
  else
  begin
    Control.SetSize(Classes.Point(Size.X, Size.Y));
  end;
end;
initialization
  InterfaceStateOverrideClass := TInterfaceStateOverrideView;
  InterfaceTextOverrideClass := TInterfaceTextOverrideView;
  InterfaceImageOverrideClass := TInterfaceImageOverrideView;
  InterfacePosOverrideClass := TInterfacePosOverrideView;
  InterfaceSizeOverrideClass := TInterfaceSizeOverrideView;
end.
