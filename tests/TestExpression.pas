unit TestExpression;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunExpressionTests;
implementation
uses
  SysUtils,
  EC_Expression,
  TestSupport;
const
  Script =
      'int a; int b; int c; int d; int sum; int i; float f; str s; str t;'#13#10
          + 'a = 1 + 2 * 3; // precedence'#13#10
          + 'b = (a - 10) * -2;'#13#10
          + 'c = 17 % 5 + (6 & 3) + (1 << 4);'#13#10
          + 'd = (a == 7) && (b > 5) && !(a < 0);'#13#10
          + 'f = 7.5 / 2;'#13#10
          + 's = "ab" + ''cd'';'#13#10
          + 't = s + a;'#13#10
          + 'sum = 0; i = 0;'#13#10
          + 'while (i < 5) { sum = sum + i; i = i + 1; }'#13#10
          + 'if (sum >= 10) { sum = sum * 100; } else { sum = -1; }'#13#10;

function CompileScript(Code: TCodeEC; const Text: WideString): WideString;
var
  Analyzer: TCodeAnalyzerEC;
begin
  Analyzer := TCodeAnalyzerEC.Create;
  try
    Analyzer.Tokenize(Text);
    Analyzer.RemoveComments;
    Analyzer.RemoveNewlines;
    Analyzer.RemoveWhitespace;
    Result := Analyzer.ValidateDelimiters;
    if Result = '' then
      Code.Compile(Analyzer, nil, nil, nil, nil, Result);
  finally
    Analyzer.Free;
  end;
end;

procedure RunExpressionTests;
var
  Code: TCodeEC;
  Process: TCodeProcessEC;
  Error: WideString;
begin
  Code := TCodeEC.Create;
  Process := TCodeProcessEC.Create;
  try
    Error := CompileScript(Code, Script);
    CheckText('', Error, 'Script compiles');
    if Error = '' then
    begin
      Code.Run(Process);
      CheckInt(7, Code.LocalVar.GetVar('a').GetInt, 'Script precedence');
      CheckInt(6, Code.LocalVar.GetVar('b').GetInt, 'Script unary minus');
      CheckInt(20, Code.LocalVar.GetVar('c').GetInt, 'Script modulo and bit operators');
      CheckInt(1, Code.LocalVar.GetVar('d').GetInt, 'Script comparisons');
      CheckFloat(3.75, Code.LocalVar.GetVar('f').GetFloat, 1e-9, 'Script float division');
      CheckText('abcd', Code.LocalVar.GetVar('s').GetString, 'Script string concatenation');
      CheckText('abcd7', Code.LocalVar.GetVar('t').GetString, 'Script string plus int');
      CheckInt(1000, Code.LocalVar.GetVar('sum').GetInt, 'Script while and if');
    end;

    Code.Clear;
    Error := CompileScript(Code, 'int x; x = (1 + 2;');
    Check(Error <> '', 'Script unbalanced parenthesis is rejected');
  except
    on E: Exception do
      ReportException('Script', E);
  end;
  Process.Free;
  Code.Free;
end;

end.
