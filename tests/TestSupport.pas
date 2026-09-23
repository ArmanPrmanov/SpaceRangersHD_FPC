unit TestSupport;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
uses
  SysUtils;
procedure Check(Condition: Boolean; const Name: string);
procedure CheckInt(Expected: Int64; Actual: Int64; const Name: string);
procedure CheckHex(Expected: Cardinal; Actual: Cardinal; const Name: string);
procedure CheckFloat(Expected: Double; Actual: Double; Tolerance: Double; const Name: string);
procedure CheckText(const Expected: WideString; const Actual: WideString; const Name: string);
procedure ReportException(const Name: string; const Error: Exception);
procedure Fail(const Name: string; const Detail: string);
function CheckCount: Integer;
function FailureCount: Integer;
implementation
var
  Checks: Integer;
  Failures: Integer;

procedure Fail(const Name: string; const Detail: string);
begin
  Inc(Failures);
  WriteLn('FAIL ', Name, ': ', Detail);
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  if not Condition then
    Fail(Name, 'condition is false');
end;

procedure CheckInt(Expected: Int64; Actual: Int64; const Name: string);
begin
  Inc(Checks);
  if Expected <> Actual then
    Fail(Name, Format('expected %d, got %d', [Expected, Actual]));
end;

procedure CheckHex(Expected: Cardinal; Actual: Cardinal; const Name: string);
begin
  Inc(Checks);
  if Expected <> Actual then
    Fail(Name, Format('expected $%.8x, got $%.8x', [Expected, Actual]));
end;

procedure CheckFloat(Expected: Double; Actual: Double; Tolerance: Double; const Name: string);
begin
  Inc(Checks);
  if Abs(Expected - Actual) > Tolerance then
    Fail(Name, Format('expected %g, got %g', [Expected, Actual]));
end;

// Console code pages vary; show non-ASCII characters as escapes.
function Printable(const Text: WideString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Text) do
    if (Ord(Text[i]) >= 32) and (Ord(Text[i]) < 127) then
      Result := Result + Char(Ord(Text[i]))
    else
      Result := Result + Format('\u%.4x', [Ord(Text[i])]);
end;

procedure CheckText(const Expected: WideString; const Actual: WideString; const Name: string);
begin
  Inc(Checks);
  if Expected <> Actual then
    Fail(Name, Format('expected "%s", got "%s"', [Printable(Expected), Printable(Actual)]));
end;

procedure ReportException(const Name: string; const Error: Exception);
begin
  Fail(Name, Error.ClassName + ': ' + Error.Message);
  DumpExceptionBackTrace(Output);
end;

function CheckCount: Integer;
begin
  Result := Checks;
end;

function FailureCount: Integer;
begin
  Result := Failures;
end;

end.
