// Module resolution hooks so `node --test` can run the TypeScript sources
// directly: they map the app's "@/..." alias and add the file extensions that
// Metro normally fills in.
import { existsSync } from 'node:fs';
import { dirname, resolve as resolvePath } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolvePath(dirname(fileURLToPath(import.meta.url)), '..');

export async function resolve(specifier, context, next) {
  let base = null;
  if (specifier.startsWith('@/')) {
    base = resolvePath(root, 'src', specifier.slice(2));
  } else if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
    base = resolvePath(dirname(fileURLToPath(context.parentURL)), specifier);
  }

  if (base) {
    for (const candidate of [`${base}.ts`, `${base}.tsx`, `${base}/index.ts`, base]) {
      if (existsSync(candidate)) {
        return { url: pathToFileURL(candidate).href, shortCircuit: true };
      }
    }
  }

  return next(specifier, context);
}
