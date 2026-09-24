{$EXCESSPRECISION OFF}
unit SaveTrace;

// CHANGE: ENHANCEMENT - Debug index of where each object starts in a written galaxy, so
// that a byte offset in two differing state dumps can be named. Writers report here; the
// hook is nil except while the headless runner dumps state.
interface
type
  TSaveTraceHook = procedure(const Kind: AnsiString; Id: Cardinal; Offset: Integer);
var
  SaveTraceHook: TSaveTraceHook;
procedure TraceSave(const Kind: AnsiString; Id: Cardinal; Offset: Integer); inline;
implementation

procedure TraceSave(const Kind: AnsiString; Id: Cardinal; Offset: Integer);
begin
  if Assigned(SaveTraceHook) then
    SaveTraceHook(Kind, Id, Offset);
end;

end.
