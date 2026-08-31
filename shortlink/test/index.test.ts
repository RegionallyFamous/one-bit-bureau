import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { handleRequest } from "../src/handler";

const installScript = readFileSync(new URL("../src/install.sh", import.meta.url), "utf8");
const handle = (request: Request) => handleRequest(request, installScript);

describe("One-Bit Bureau installer Worker", () => {
  it("serves a memorable landing page", async () => {
    const response = handle(new Request("https://bureau.regionallyfamous.com/"));

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(await response.text()).toContain(
      "bash &lt;(curl -fsSL https://bureau.regionallyfamous.com/install)"
    );
  });

  it.each(["/install", "/i", "/install/"])("serves the same auditable script at %s", async (path) => {
    const response = handle(new Request(`https://bureau.regionallyfamous.com${path}`));
    const body = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/x-shellscript; charset=utf-8");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(body).toContain("#!/bin/bash");
    expect(body).toContain("omarchy plugin add \"$REPO_URL\" --yes");
    expect(body).toContain("omarchy plugin update \"$PLUGIN_ID\" --yes");
    expect(body).toContain("--adopt-plugin --yes");
  });

  it("returns headers without a body for HEAD", async () => {
    const response = handle(
      new Request("https://bureau.regionallyfamous.com/install", { method: "HEAD" })
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/x-shellscript; charset=utf-8");
    expect(await response.text()).toBe("");
  });

  it("redirects project shortcuts only to canonical GitHub destinations", () => {
    const source = handle(new Request("https://bureau.regionallyfamous.com/source"));
    const release = handle(new Request("https://bureau.regionallyfamous.com/release"));

    expect(source.status).toBe(302);
    expect(source.headers.get("location")).toBe(
      "https://github.com/RegionallyFamous/one-bit-bureau"
    );
    expect(release.headers.get("location")).toBe(
      "https://github.com/RegionallyFamous/one-bit-bureau/releases/latest"
    );
  });

  it("rejects mutation methods and unknown paths", async () => {
    const mutation = handle(
      new Request("https://bureau.regionallyfamous.com/install", { method: "POST" })
    );
    const missing = handle(new Request("https://bureau.regionallyfamous.com/nope"));

    expect(mutation.status).toBe(405);
    expect(mutation.headers.get("allow")).toBe("GET, HEAD");
    expect(missing.status).toBe(404);
    expect(await missing.text()).toBe("Not Found\n");
  });
});
