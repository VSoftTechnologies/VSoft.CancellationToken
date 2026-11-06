unit VSoft.CancellationToken.Tests;

interface

uses
  DUnitX.TestFramework,
  VSoft.CancellationToken;

type
  [TestFixture]
  TCancellationTokenTests = class
  private
    FTokenSource : ICancellationTokenSource;

  public

    [SetupFixture]
    procedure SetupFixture;

    [TeardownFixture]
    procedure TeardownFixture;

    [Test]
    procedure TestCancel;

    [Test]
    procedure TestCancelUsingHandle;

    // Cancel on one thread racing Reset on another must never leave the
    // event set while IsCancelled is False (or the reverse).
    [Test]
    procedure TestCancelResetRace;

  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Diagnostics,
  WinApi.Windows;

const
  cRaceRounds = 50000;
  cRaceJitter = 64;


{ TCancellationTokenTests }

procedure TCancellationTokenTests.SetupFixture;
begin
  FTokenSource := TCancellationTokenSourceFactory.Create;
end;

procedure TCancellationTokenTests.TeardownFixture;
begin
  FTokenSource := nil;
end;

procedure TCancellationTokenTests.TestCancel;
var
  token : ICancellationToken;
  cancelled : boolean;
begin
  FTokenSource.Reset;
  cancelled := false;
  token := FTokenSource.Token;
  TThread.CreateAnonymousThread(
    procedure
    var
      ltoken : ICancellationToken;
    begin
      lToken := token;
      while not lToken.IsCancelled do
      begin
        Sleep(1);
        cancelled := lToken.IsCancelled;
      end;
    end).Start;
//    testThread.Start;
    TThread.Sleep(100);
    FTokenSource.Cancel;
    TThread.Sleep(50);
    Assert.IsTrue(cancelled);
end;


procedure TCancellationTokenTests.TestCancelUsingHandle;
var
  token : ICancellationToken;
  cancelled : boolean;
begin
  FTokenSource.Reset;
  cancelled := false;
  token := FTokenSource.Token;
  TThread.CreateAnonymousThread(
    procedure
    var
      res : integer;
      ltoken : ICancellationToken;
      event : TEvent;
      handles : array[0..1] of THandle;
    begin
      lToken := token;
      event := TEvent.Create(nil,false, false,'');
      handles[0] := lToken.Handle;
      handles[1] := event.Handle;
      try
        while true do
        begin
          res := WaitForMultipleObjects(2, @handles, false, 2000);
          if res = WAIT_OBJECT_0 then
          begin
            //token was cancelled
            cancelled := true;
            exit;
          end;
        end;

      finally
        event.Free;
      end;
    end).Start;
    TThread.Sleep(100);
    FTokenSource.Cancel;
    TThread.Sleep(50);
    Assert.IsTrue(cancelled);
end;

procedure TCancellationTokenTests.TestCancelResetRace;
var
  source : ICancellationTokenSource;
  token : ICancellationToken;
  worker : TThread;
  roundNo : integer;
  done : integer;
  stop : integer;
  i : integer;
  seed : UInt64;
  stopwatch : TStopwatch;
  eventSet : boolean;
  mismatches : integer;
  firstBad : integer;
begin
  //A source of its own: the fixture's one is shared with the other tests.
  source := TCancellationTokenSourceFactory.Create;
  token := source.Token;
  roundNo := 0;
  done := 0;
  stop := 0;
  mismatches := 0;
  firstBad := 0;

  //Calls Cancel once per round, after a pseudo-random spin, so it lands
  //anywhere relative to the Reset on the test thread.
  worker := TThread.CreateAnonymousThread(
    procedure
    var
      seen : integer;
      current : integer;
      workerSeed : UInt64;
    begin
      seen := 0;
      workerSeed := 1;
      while TInterlocked.CompareExchange(stop, 0, 0) = 0 do
      begin
        current := TInterlocked.CompareExchange(roundNo, 0, 0);
        if current <> seen then
        begin
          seen := current;
          workerSeed := (workerSeed * 1664525 + 1013904223) and $FFFFFFFF;
          TThread.SpinWait((workerSeed shr 16) mod cRaceJitter);
          source.Cancel;
          TInterlocked.Increment(done);
        end;
      end;
    end);
  worker.FreeOnTerminate := false;
  worker.Start;
  try
    seed := 12345;
    for i := 1 to cRaceRounds do
    begin
      TInterlocked.Increment(roundNo);
      seed := (seed * 1664525 + 1013904223) and $FFFFFFFF;
      TThread.SpinWait((seed shr 16) mod cRaceJitter);
      source.Reset;
      //Wait for this round's Cancel, then the token must be consistent.  The stall
      //limit is per round, so a slow machine is not failed by the total time.
      stopwatch := TStopwatch.StartNew;
      while TInterlocked.CompareExchange(done, 0, 0) < i do
        if stopwatch.ElapsedMilliseconds > 60000 then
          Assert.Fail(Format('The Cancel thread stalled in round %d', [i]));
      eventSet := token.WaitFor(0) = wrSignaled;
      if token.IsCancelled <> eventSet then
      begin
        Inc(mismatches);
        if firstBad = 0 then
          firstBad := i;
      end;
    end;
  finally
    TInterlocked.Exchange(stop, 1);
    worker.WaitFor;
    worker.Free;
  end;

  Assert.AreEqual(0, mismatches, Format('%d of %d rounds ended with IsCancelled <> the event state (first: round %d)',
                                        [mismatches, cRaceRounds, firstBad]));
  //No check that both outcomes (ended cancelled, ended reset) occurred: the scheduler may
  //legitimately order Reset before Cancel every round, and that must not fail the test.
  //The assertion above is the real one, and it holds whichever order the calls take.
end;

initialization
  TDUnitX.RegisterTestFixture(TCancellationTokenTests);

end.
