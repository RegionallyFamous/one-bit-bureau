const ORIGIN = "https://bureau.regionallyfamous.com";
const SOURCE_URL = "https://github.com/RegionallyFamous/one-bit-bureau";
const RELEASE_URL = `${SOURCE_URL}/releases/latest`;
const QUICK_INSTALL = `bash <(curl -fsSL ${ORIGIN}/install)`;
const COMMON_HEADERS: Record<string, string> = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Permissions-Policy": "camera=(), geolocation=(), microphone=()",
  "Referrer-Policy": "no-referrer",
  "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY"
};

function htmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function landingPage(): string {
  const quickInstall = htmlEscape(QUICK_INSTALL);
  const manualInstall = htmlEscape(
    `omarchy plugin add ${SOURCE_URL}.git --yes && bash "$HOME/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/setup" --adopt-plugin`
  );

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>One-Bit Bureau — Install</title>
  <style>
    :root { color-scheme: light; font-family: "Courier New", monospace; background: #b9b9b9; color: #111; }
    * { box-sizing: border-box; }
    body { min-height: 100vh; margin: 0; display: grid; place-items: center; padding: 24px; background-color: #b9b9b9; background-image: repeating-conic-gradient(#aaa 0 25%, #c8c8c8 0 50%); background-size: 4px 4px; }
    main { width: min(760px, 100%); border: 3px solid #111; background: #fff; box-shadow: 10px 10px 0 #111; }
    header { min-height: 38px; display: grid; grid-template-columns: 38px 1fr 38px; align-items: center; border-bottom: 3px solid #111; background: repeating-linear-gradient(0deg, #fff 0 2px, #111 2px 4px); }
    header span { grid-column: 2; justify-self: center; padding: 3px 12px; border: 2px solid #111; background: #fff; font-weight: 700; }
    header::before { content: ""; width: 16px; height: 16px; margin-left: 10px; border: 2px solid #111; background: #fff; }
    section { padding: clamp(24px, 6vw, 54px); }
    .mark { width: 72px; height: 72px; float: left; margin: 0 22px 12px 0; display: grid; place-items: center; border: 3px solid #111; border-radius: 50%; font-size: 42px; font-weight: 900; }
    h1 { margin: 0 0 10px; font-size: clamp(30px, 7vw, 56px); line-height: .9; letter-spacing: -4px; }
    .lede { max-width: 58ch; margin: 0 0 34px; font-weight: 700; line-height: 1.45; }
    h2 { clear: both; margin: 28px 0 8px; font-size: 16px; text-transform: uppercase; }
    code { display: block; overflow-x: auto; padding: 16px; border: 2px solid #111; background: #f1f1f1; color: #111; font: 700 14px/1.5 "Courier New", monospace; white-space: nowrap; }
    p { line-height: 1.5; }
    a { color: #111; font-weight: 700; text-decoration-thickness: 2px; }
    nav { display: flex; flex-wrap: wrap; gap: 18px; margin-top: 28px; padding-top: 18px; border-top: 2px solid #111; }
    .fine { font-size: 12px; }
  </style>
</head>
<body>
  <main>
    <header><span>One-Bit Bureau Installer</span></header>
    <section>
      <div class="mark" aria-hidden="true">B</div>
      <h1>Your desk is ready.</h1>
      <p class="lede">One memorable address installs the complete vintage Macintosh-inspired Omarchy plugin and theme package.</p>
      <h2>Quick install</h2>
      <code>${quickInstall}</code>
      <p class="fine">The tiny bootstrap uses Omarchy’s validated Git installer and keeps the existing trust prompt. Inspect it first with <code>curl -fsSL ${ORIGIN}/install</code></p>
      <h2>Audit-first install</h2>
      <code>${manualInstall}</code>
      <nav aria-label="Project links">
        <a href="/source">Source</a>
        <a href="/release">Latest release</a>
        <a href="/install">Installer script</a>
      </nav>
    </section>
  </main>
</body>
</html>`;
}

function response(
  request: Request,
  body: BodyInit | null,
  status: number,
  headers: Record<string, string>
): Response {
  return new Response(request.method === "HEAD" ? null : body, {
    status,
    headers: { ...COMMON_HEADERS, ...headers }
  });
}

function redirect(request: Request, location: string): Response {
  return response(request, null, 302, {
    "Cache-Control": "public, max-age=300",
    Location: location
  });
}

export function handleRequest(request: Request, installScriptSource: string): Response {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return response(request, "Method Not Allowed\n", 405, {
      Allow: "GET, HEAD",
      "Cache-Control": "no-store",
      "Content-Type": "text/plain; charset=utf-8"
    });
  }

  const pathname = new URL(request.url).pathname.replace(/\/+$/, "") || "/";

  if (pathname === "/") {
    return response(request, landingPage(), 200, {
      "Cache-Control": "public, max-age=300",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "Content-Type": "text/html; charset=utf-8"
    });
  }

  if (pathname === "/install" || pathname === "/i") {
    const installScript = installScriptSource.endsWith("\n")
      ? installScriptSource
      : `${installScriptSource}\n`;
    return response(request, installScript, 200, {
      "Cache-Control": "public, max-age=300",
      "Content-Disposition": "inline; filename=one-bit-bureau-install",
      "Content-Type": "text/x-shellscript; charset=utf-8"
    });
  }

  if (pathname === "/source") {
    return redirect(request, SOURCE_URL);
  }

  if (pathname === "/release") {
    return redirect(request, RELEASE_URL);
  }

  return response(request, "Not Found\n", 404, {
    "Cache-Control": "no-store",
    "Content-Type": "text/plain; charset=utf-8"
  });
}
