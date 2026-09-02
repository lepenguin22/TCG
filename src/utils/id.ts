let counter = 0;

/** Small, dependency free unique id. Unique per install, which is all we need. */
export function createId(prefix = 'id'): string {
  counter += 1;
  const random = Math.random().toString(36).slice(2, 8);
  return `${prefix}_${Date.now().toString(36)}${counter.toString(36)}${random}`;
}
