import { describe, expect, it } from "vitest";

import { handleRequest } from "../src/handler";

const handle = (request: Request) => handleRequest(request);

describe("One-Bit Bureau installer Worker", () => {
  it("serves a memorable landing page", async () => {
    const response = handle(new Request("https://bureau.regionallyfamous.com/"));

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    const body = await response.text();
    expect(body).toContain("digest-verified release");
    expect(body).toContain(".immutable == true");
    expect(body).toContain("sha256sum");
    expect(body).not.toContain("&lt;(curl");
  });

  it.each(["/install", "/i", "/install/"])("retires the mutable shell endpoint at %s", async (path) => {
    const response = handle(new Request(`https://bureau.regionallyfamous.com${path}`));
    const body = await response.text();

    expect(response.status).toBe(410);
    expect(response.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(body).toContain("remote shell bootstrap has been retired");
    expect(body).not.toContain("#!/bin/bash");
  });

  it("returns headers without a body for HEAD", async () => {
    const response = handle(
      new Request("https://bureau.regionallyfamous.com/install", { method: "HEAD" })
    );

    expect(response.status).toBe(410);
    expect(response.headers.get("content-type")).toBe("text/plain; charset=utf-8");
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
