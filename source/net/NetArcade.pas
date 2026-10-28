{$EXCESSPRECISION OFF}
unit NetArcade;

// CHANGE: ENHANCEMENT - The inputs of a co-op black hole battle that came over the network
// (docs/network.md, Co-op black hole battles). NetHost and NetClient store every ArcadeInput
// they receive here as it comes, whatever the screen: a partner may open the battle and send
// its first ticks before this machine has opened it. The battle (through NetPlay's hooks)
// takes them by battle, human and tick. Only the UI thread uses it.
interface
uses
  NetProtocol;

// Keeps Message; a later one for the same human and tick replaces it.
procedure StoreArcadeInput(const Message: TArcadeInputMessage);
// The input of HumanId for Tick of Battle, when it has come.
function FindArcadeInput(Battle: Cardinal; HumanId, Tick: Integer;
    out Message: TArcadeInputMessage): Boolean;
// Forgets every input of other battles than Battle.
procedure KeepOnlyArcadeBattle(Battle: Cardinal);

implementation

const
  // Ticks kept per human: far more than the input delay and any stall needs.
  RingSize = 4096;
  // Humans kept at once; the oldest slot goes to a new one.
  SlotCount = 4;

type
  TInputEntry = record
    Valid: Boolean;
    Message: TArcadeInputMessage;
  end;
  TInputSlot = record
    Battle: Cardinal;
    HumanId: Integer;
    Used: Boolean;
    Stamp: Cardinal;
    Ring: array[0..RingSize - 1] of TInputEntry;
  end;

var
  Slots: array[0..SlotCount - 1] of TInputSlot;
  NextStamp: Cardinal;

function FindSlot(Battle: Cardinal; HumanId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to SlotCount - 1 do
    if Slots[I].Used and (Slots[I].Battle = Battle) and (Slots[I].HumanId = HumanId) then
      Exit(I);
  Result := -1;
end;

procedure StoreArcadeInput(const Message: TArcadeInputMessage);
var
  I, Oldest: Integer;
begin
  if Message.Tick < 0 then
    Exit;
  I := FindSlot(Message.Battle, Message.HumanId);
  if I < 0 then
  begin
    Oldest := 0;
    for I := 0 to SlotCount - 1 do
    begin
      if not Slots[I].Used then
      begin
        Oldest := I;
        Break;
      end;
      if Slots[I].Stamp < Slots[Oldest].Stamp then
        Oldest := I;
    end;
    I := Oldest;
    FillChar(Slots[I], SizeOf(Slots[I]), 0);
    Slots[I].Used := True;
    Slots[I].Battle := Message.Battle;
    Slots[I].HumanId := Message.HumanId;
  end;
  Inc(NextStamp);
  Slots[I].Stamp := NextStamp;
  Slots[I].Ring[Message.Tick mod RingSize].Valid := True;
  Slots[I].Ring[Message.Tick mod RingSize].Message := Message;
end;

function FindArcadeInput(Battle: Cardinal; HumanId, Tick: Integer;
    out Message: TArcadeInputMessage): Boolean;
var
  I: Integer;
begin
  Result := False;
  Message := Default(TArcadeInputMessage);
  if Tick < 0 then
    Exit;
  I := FindSlot(Battle, HumanId);
  if I < 0 then
    Exit;
  if Slots[I].Ring[Tick mod RingSize].Valid
      and (Slots[I].Ring[Tick mod RingSize].Message.Tick = Tick) then
  begin
    Message := Slots[I].Ring[Tick mod RingSize].Message;
    Result := True;
  end;
end;

procedure KeepOnlyArcadeBattle(Battle: Cardinal);
var
  I: Integer;
begin
  for I := 0 to SlotCount - 1 do
    if Slots[I].Used and (Slots[I].Battle <> Battle) then
      Slots[I].Used := False;
end;

end.
