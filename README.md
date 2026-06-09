# VSoft.CancellationToken

This is a simple library for Delphi that provides a CancellationTokenSource and CancellationToken much like those in .NET

## Supported Compilers & Platforms

| Compiler            | Win32 | Win64 | macOS (Intel) | macOS (Apple Silicon) | Linux64 |
|---------------------|:-----:|:-----:|:-------------:|:---------------------:|:-------:|
| Delphi XE2 – 10.1   |  ✅   |  ✅   |               |                       |         |
| Delphi 10.2         |  ✅   |  ✅   |               |                       |   ✅    |
| Delphi 10.3 – 10.4  |  ✅   |  ✅   |      ✅       |                       |   ✅    |
| Delphi 11.0 – 13.0  |  ✅   |  ✅   |      ✅       |          ✅           |   ✅    |

macOS support requires Delphi 10.3 or later (`OSX64`); Apple Silicon (`OSXARM64`)
requires Delphi 11.0 or later. Linux (`Linux64`) requires Delphi 10.2 or later and
the **Enterprise or Architect** edition (the Linux target is not available in
Professional).

## Usage

Create a `ICancellationTokenSource`, pass its `Token` to the work you want to be
able to cancel, then call `Cancel` when you want to signal cancellation.

```pascal
uses
  VSoft.CancellationToken;

var
  source : ICancellationTokenSource;
  token  : ICancellationToken;
begin
  source := TCancellationTokenSourceFactory.Create;
  token  := source.Token;

  // pass token to your worker thread/method, which periodically checks:
  //   if token.IsCancelled then Exit;
  // or blocks with:
  //   token.WaitFor(timeoutMs);

  // when you want to cancel:
  source.Cancel;
end;
```

### Platform notes

The token exposes the underlying wait primitive so callers can wait on it
together with other handles/events:

* On Windows, `ICancellationToken.Handle` returns the Win32 event `THandle`.
  Do **not** call `SetEvent` on this handle directly.
* On other platforms (macOS, Linux), `ICancellationToken.Event` returns the
  `System.SyncObjs.TEvent` instance.

The cross-platform `WaitFor` and `IsCancelled` methods are available everywhere
and should be preferred where possible.
