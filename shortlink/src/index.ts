import installScript from "./install.sh";
import { handleRequest } from "./handler";

export default {
  fetch(request: Request): Response {
    return handleRequest(request, installScript);
  }
} satisfies ExportedHandler<Env>;
