import { handleRequest } from "./handler";

export default {
  fetch(request: Request): Response {
    return handleRequest(request);
  }
} satisfies ExportedHandler<Env>;
