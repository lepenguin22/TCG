import type { DeckView, StatGroup, ValidationIssue } from '@/games/types';
import type { CardDefinition } from '@/types';
import {
  CARD_TYPE_OPTIONS,
  FORMAT_CASUAL,
  FORMAT_PREMIUM,
  FORMAT_STANDARD,
  GRADE_OPTIONS,
  NATION_OPTIONS,
  TRIGGER_OPTIONS,
  ZONE_G,
  ZONE_MAIN,
  ZONE_RIDE,
  optionColor,
  optionLabel,
} from './data';

interface Slot {
  card: CardDefinition;
  quantity: number;
}

export function slotsInZone(view: DeckView, zoneId: string): Slot[] {
  return view.items
    .filter((i) => i.entry.zoneId === zoneId)
    .map((i) => ({ card: i.card, quantity: i.entry.quantity }));
}

export function countZone(view: DeckView, zoneId: string): number {
  return slotsInZone(view, zoneId).reduce((sum, s) => sum + s.quantity, 0);
}

function isTrigger(card: CardDefinition): boolean {
  return card.attributes.cardType === 'trigger' && !!card.attributes.trigger;
}

function tally(slots: Slot[], pick: (card: CardDefinition) => string | undefined): Map<string, number> {
  const out = new Map<string, number>();
  for (const slot of slots) {
    const key = pick(slot.card);
    if (key === undefined) continue;
    out.set(key, (out.get(key) ?? 0) + slot.quantity);
  }
  return out;
}

/** Copies of each card *name*, which is what the four-copy rule counts. */
function copiesByName(slots: Slot[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const slot of slots) {
    const key = slot.card.name.trim().toLowerCase();
    if (!key) continue;
    out.set(key, (out.get(key) ?? 0) + slot.quantity);
  }
  return out;
}

function displayName(slots: Slot[], lowerName: string): string {
  return slots.find((s) => s.card.name.trim().toLowerCase() === lowerName)?.card.name ?? lowerName;
}

export function validateVanguard(view: DeckView): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const formatId = view.format.id;
  const ride = slotsInZone(view, ZONE_RIDE);
  const main = slotsInZone(view, ZONE_MAIN);
  const gZone = slotsInZone(view, ZONE_G);
  const rideCount = ride.reduce((s, x) => s + x.quantity, 0);
  const mainCount = main.reduce((s, x) => s + x.quantity, 0);
  const gCount = gZone.reduce((s, x) => s + x.quantity, 0);
  const strict = formatId !== FORMAT_CASUAL;

  if (view.items.length === 0) {
    issues.push({ level: 'warning', message: 'This deck is empty. Add cards to start checking it against the rules.' });
    return issues;
  }

  // --- Deck sizes -----------------------------------------------------------
  if (strict && mainCount !== 50) {
    issues.push({
      level: 'error',
      message: `Main deck holds ${mainCount} cards. It must hold exactly 50.`,
    });
  }

  if (formatId === FORMAT_STANDARD) {
    if (rideCount !== 4) {
      issues.push({ level: 'error', message: `Ride deck holds ${rideCount} cards. It must hold exactly 4.` });
    }
    const rideGrades = tally(ride, (c) => c.attributes.grade);
    for (const grade of ['0', '1', '2', '3']) {
      const n = rideGrades.get(grade) ?? 0;
      if (n === 0) {
        issues.push({ level: 'error', message: `Ride deck is missing its grade ${grade} card.` });
      } else if (n > 1) {
        issues.push({ level: 'error', message: `Ride deck has ${n} grade ${grade} cards. It takes exactly one of each grade 0-3.` });
      }
    }
    const rideTriggers = ride.filter((s) => isTrigger(s.card));
    for (const slot of rideTriggers) {
      issues.push({ level: 'error', message: `"${slot.card.name}" is a trigger unit, so it cannot go in the ride deck.` });
    }
    for (const slot of [...ride, ...main]) {
      if (slot.card.attributes.grade === '4' || slot.card.attributes.cardType === 'g-unit') {
        issues.push({ level: 'error', message: `"${slot.card.name}" is a G unit, which is Premium only.` });
      }
    }
    if (gCount > 0) {
      issues.push({ level: 'error', message: 'Standard decks do not use a G zone. Switch the deck to Premium or move those cards out.' });
    }
  }

  if (formatId === FORMAT_PREMIUM) {
    if (gCount > 16) {
      issues.push({ level: 'error', message: `G zone holds ${gCount} cards. The limit is 16.` });
    } else if (gCount > 0 && gCount < 16) {
      issues.push({ level: 'warning', message: `G zone holds ${gCount} of a possible 16 cards.` });
    }
    for (const slot of gZone) {
      if (slot.card.attributes.grade !== '4' && slot.card.attributes.cardType !== 'g-unit') {
        issues.push({ level: 'error', message: `"${slot.card.name}" is not a G unit, so it cannot go in the G zone.` });
      }
    }
    for (const slot of main) {
      if (slot.card.attributes.grade === '4' || slot.card.attributes.cardType === 'g-unit') {
        issues.push({ level: 'error', message: `"${slot.card.name}" is a G unit and belongs in the G zone, not the main deck.` });
      }
    }
    const mainGrades = tally(main, (c) => c.attributes.grade);
    if ((mainGrades.get('0') ?? 0) === 0) {
      issues.push({ level: 'error', message: 'Premium decks need a grade 0 in the main deck to use as the first vanguard.' });
    }
    if (rideCount > 0) {
      issues.push({ level: 'warning', message: 'Premium does not use a ride deck. Those cards are not counted towards the main deck.' });
    }
  }

  // --- Four copies of a name ------------------------------------------------
  const playCopies = copiesByName([...ride, ...main]);
  for (const [name, count] of playCopies) {
    if (count > 4) {
      issues.push({
        level: strict ? 'error' : 'warning',
        message: `"${displayName([...ride, ...main], name)}" appears ${count} times. Only 4 copies of a card name are allowed.`,
      });
    }
  }
  const gCopies = copiesByName(gZone);
  for (const [name, count] of gCopies) {
    if (count > 4) {
      issues.push({
        level: strict ? 'error' : 'warning',
        message: `"${displayName(gZone, name)}" appears ${count} times in the G zone. Only 4 copies of a card name are allowed.`,
      });
    }
  }

  // --- Triggers -------------------------------------------------------------
  const triggerSlots = main.filter((s) => isTrigger(s.card));
  const triggerCount = triggerSlots.reduce((s, x) => s + x.quantity, 0);
  const byTrigger = tally(triggerSlots, (c) => c.attributes.trigger);
  const heal = byTrigger.get('heal') ?? 0;
  const over = byTrigger.get('over') ?? 0;

  if (strict && triggerCount !== 16) {
    issues.push({
      level: 'error',
      message: `Main deck has ${triggerCount} trigger units. A legal deck runs exactly 16.`,
    });
  }
  if (heal > 4) {
    issues.push({ level: 'error', message: `${heal} heal triggers. The limit is 4.` });
  }
  if (over > 1) {
    issues.push({ level: 'error', message: `${over} over triggers. The limit is 1.` });
  }

  // --- Soft advice ----------------------------------------------------------
  if (formatId !== FORMAT_CASUAL && mainCount > 0) {
    const mainGrades = tally(main, (c) => c.attributes.grade);
    const sentinels = main
      .filter((s) => s.card.attributes.cardType === 'sentinel')
      .reduce((s, x) => s + x.quantity, 0);
    if (sentinels === 0) {
      issues.push({ level: 'warning', message: 'No sentinels in the main deck. Most lists run 4 perfect guards.' });
    } else if (sentinels > 4) {
      issues.push({ level: 'warning', message: `${sentinels} sentinels. Only 4 copies of one name are legal, so check these are different cards.` });
    }
    if ((mainGrades.get('3') ?? 0) === 0) {
      issues.push({ level: 'warning', message: 'No grade 3s in the main deck.' });
    }
  }

  return issues;
}

export function vanguardStats(view: DeckView): StatGroup[] {
  const main = slotsInZone(view, ZONE_MAIN);
  const ride = slotsInZone(view, ZONE_RIDE);
  const gZone = slotsInZone(view, ZONE_G);
  const everything = [...main, ...ride, ...gZone];
  const groups: StatGroup[] = [];

  const mainCount = main.reduce((s, x) => s + x.quantity, 0);
  const grades = tally(main, (c) => c.attributes.grade ?? '0');
  groups.push({
    title: 'Grade curve',
    caption: `${mainCount} cards in the main deck`,
    bars: GRADE_OPTIONS.filter((g) => g.value !== '4' || (grades.get('4') ?? 0) > 0).map((g) => ({
      label: `Grade ${g.value}`,
      value: grades.get(g.value) ?? 0,
      color: g.color,
    })),
  });

  const triggerSlots = main.filter((s) => isTrigger(s.card));
  const triggers = tally(triggerSlots, (c) => c.attributes.trigger);
  const triggerCount = triggerSlots.reduce((s, x) => s + x.quantity, 0);
  groups.push({
    title: 'Triggers',
    caption: `${triggerCount} of 16`,
    bars: TRIGGER_OPTIONS.map((t) => ({
      label: t.label,
      value: triggers.get(t.value) ?? 0,
      color: t.color,
    })).filter((b) => b.value > 0 || ['critical', 'draw', 'heal'].includes(b.label.toLowerCase())),
  });

  const types = tally(everything, (c) => c.attributes.cardType);
  groups.push({
    title: 'Card types',
    bars: CARD_TYPE_OPTIONS.map((t) => ({ label: t.label, value: types.get(t.value) ?? 0 })).filter((b) => b.value > 0),
  });

  const nations = tally(everything, (c) => c.attributes.nation);
  const nationBars = NATION_OPTIONS.map((n) => ({
    label: optionLabel(NATION_OPTIONS, n.value),
    value: nations.get(n.value) ?? 0,
    color: optionColor(NATION_OPTIONS, n.value),
  })).filter((b) => b.value > 0);
  if (nationBars.length > 0) {
    groups.push({ title: 'Nations', bars: nationBars });
  }

  return groups;
}
