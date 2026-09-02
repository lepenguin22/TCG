import assert from 'node:assert/strict';
import { test } from 'node:test';
import { getFormat } from '@/games/types';
import type { DeckView } from '@/games/types';
import type { CardDefinition, Deck } from '@/types';
import { vanguard } from './index';
import { FORMAT_PREMIUM, FORMAT_STANDARD, ZONE_G, ZONE_MAIN, ZONE_RIDE } from './data';

let seq = 0;

function card(name: string, attributes: Record<string, string>): CardDefinition {
  seq += 1;
  return {
    id: `card-${seq}`,
    gameId: 'vanguard',
    name,
    attributes,
    createdAt: 0,
    updatedAt: 0,
  };
}

function view(
  formatId: string,
  slots: { card: CardDefinition; zoneId: string; quantity: number }[],
): DeckView {
  const deck: Deck = {
    id: 'deck-1',
    gameId: 'vanguard',
    formatId,
    name: 'Test deck',
    description: '',
    accent: 'ember',
    favorite: false,
    entries: slots.map((s) => ({ cardId: s.card.id, zoneId: s.zoneId, quantity: s.quantity })),
    createdAt: 0,
    updatedAt: 0,
  };
  return {
    deck,
    format: getFormat(vanguard, formatId),
    items: slots.map((s) => ({
      entry: { cardId: s.card.id, zoneId: s.zoneId, quantity: s.quantity },
      card: s.card,
    })),
  };
}

/** A legal 50 card main deck plus a legal ride deck. */
function legalStandardDeck() {
  const slots: { card: CardDefinition; zoneId: string; quantity: number }[] = [
    { card: card('Ride G0', { grade: '0', cardType: 'normal' }), zoneId: ZONE_RIDE, quantity: 1 },
    { card: card('Ride G1', { grade: '1', cardType: 'normal' }), zoneId: ZONE_RIDE, quantity: 1 },
    { card: card('Ride G2', { grade: '2', cardType: 'normal' }), zoneId: ZONE_RIDE, quantity: 1 },
    { card: card('Ride G3', { grade: '3', cardType: 'normal' }), zoneId: ZONE_RIDE, quantity: 1 },
    // 16 triggers
    { card: card('Crit A', { grade: '0', cardType: 'trigger', trigger: 'critical' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Crit B', { grade: '0', cardType: 'trigger', trigger: 'critical' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Draw A', { grade: '0', cardType: 'trigger', trigger: 'draw' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Heal A', { grade: '0', cardType: 'trigger', trigger: 'heal' }), zoneId: ZONE_MAIN, quantity: 4 },
    // 4 sentinels
    { card: card('Perfect Guard', { grade: '1', cardType: 'sentinel' }), zoneId: ZONE_MAIN, quantity: 4 },
    // 30 more bodies
    { card: card('Grade 1 A', { grade: '1', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 1 B', { grade: '1', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 2 A', { grade: '2', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 2 B', { grade: '2', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 2 C', { grade: '2', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 3 A', { grade: '3', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 3 B', { grade: '3', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 4 },
    { card: card('Grade 3 C', { grade: '3', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 2 },
  ];
  return slots;
}

function errorsOf(v: DeckView): string[] {
  return vanguard.validate(v).filter((i) => i.level === 'error').map((i) => i.message);
}

test('a legal standard deck reports no issues', () => {
  const issues = vanguard.validate(view(FORMAT_STANDARD, legalStandardDeck()));
  assert.deepEqual(issues, [], `unexpected issues: ${JSON.stringify(issues, null, 2)}`);
});

test('main deck must hold exactly 50 cards', () => {
  const slots = legalStandardDeck();
  slots[slots.length - 1].quantity = 1; // 49 cards
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('49 cards')), errors.join('\n'));
});

test('ride deck needs one of each grade 0 to 3', () => {
  const slots = legalStandardDeck().filter((s) => s.card.name !== 'Ride G2');
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('missing its grade 2')), errors.join('\n'));
});

test('trigger units cannot sit in the ride deck', () => {
  const slots = legalStandardDeck();
  slots[0] = {
    card: card('Trigger Ride', { grade: '0', cardType: 'trigger', trigger: 'critical' }),
    zoneId: ZONE_RIDE,
    quantity: 1,
  };
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('cannot go in the ride deck')), errors.join('\n'));
});

test('the main deck must hold exactly 16 triggers', () => {
  const slots = legalStandardDeck();
  const draws = slots.find((s) => s.card.name === 'Draw A')!;
  draws.quantity = 3;
  const filler = slots.find((s) => s.card.name === 'Grade 2 A')!;
  filler.quantity = 5; // keep the deck at 50 so only the trigger count is wrong
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('15 trigger units')), errors.join('\n'));
});

test('more than four copies of a card name is illegal', () => {
  const slots = legalStandardDeck();
  slots.find((s) => s.card.name === 'Grade 2 A')!.quantity = 5;
  slots.find((s) => s.card.name === 'Grade 3 C')!.quantity = 1;
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('appears 5 times')), errors.join('\n'));
});

test('four copies of the same name split across zones is still four', () => {
  const slots = legalStandardDeck();
  // "Grade 1 A" x4 in main; put one more copy of the same *name* in the ride deck.
  slots[1] = { card: card('Grade 1 A', { grade: '1', cardType: 'normal' }), zoneId: ZONE_RIDE, quantity: 1 };
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('appears 5 times')), errors.join('\n'));
});

test('heal triggers are capped at four and over triggers at one', () => {
  const slots = legalStandardDeck();
  slots.find((s) => s.card.name === 'Crit A')!.card.attributes.trigger = 'heal';
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('8 heal triggers')), errors.join('\n'));
});

test('over triggers are capped at one', () => {
  const slots = legalStandardDeck();
  const crit = slots.find((s) => s.card.name === 'Crit B')!;
  crit.card.attributes.trigger = 'over';
  crit.quantity = 2;
  slots.find((s) => s.card.name === 'Grade 3 C')!.quantity = 4;
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('2 over triggers')), errors.join('\n'));
});

test('G units are rejected in standard', () => {
  const slots = legalStandardDeck();
  slots.push({
    card: card('Some G Unit', { grade: '4', cardType: 'g-unit' }),
    zoneId: ZONE_MAIN,
    quantity: 1,
  });
  const errors = errorsOf(view(FORMAT_STANDARD, slots));
  assert.ok(errors.some((e) => e.includes('Premium only')), errors.join('\n'));
});

test('premium rejects a non G unit in the G zone', () => {
  const slots = legalStandardDeck().filter((s) => s.zoneId !== ZONE_RIDE);
  slots.push({
    card: card('Not A G Unit', { grade: '3', cardType: 'normal' }),
    zoneId: ZONE_G,
    quantity: 1,
  });
  const errors = errorsOf(view(FORMAT_PREMIUM, slots));
  assert.ok(errors.some((e) => e.includes('cannot go in the G zone')), errors.join('\n'));
});

test('premium allows sixteen G units', () => {
  const slots = legalStandardDeck().filter((s) => s.zoneId !== ZONE_RIDE);
  for (let i = 0; i < 4; i += 1) {
    slots.push({
      card: card(`G Unit ${i}`, { grade: '4', cardType: 'g-unit' }),
      zoneId: ZONE_G,
      quantity: 4,
    });
  }
  const errors = errorsOf(view(FORMAT_PREMIUM, slots));
  assert.deepEqual(errors, [], errors.join('\n'));
});

test('the casual format does not enforce deck size', () => {
  const slots = [
    { card: card('Just one card', { grade: '3', cardType: 'normal' }), zoneId: ZONE_MAIN, quantity: 1 },
  ];
  const errors = errorsOf(view('casual', slots));
  assert.deepEqual(errors, [], errors.join('\n'));
});

test('the grade curve counts the main deck', () => {
  const groups = vanguard.stats(view(FORMAT_STANDARD, legalStandardDeck()));
  const curve = groups.find((g) => g.title === 'Grade curve')!;
  const total = curve.bars.reduce((sum, b) => sum + b.value, 0);
  assert.equal(total, 50);
  const triggers = groups.find((g) => g.title === 'Triggers')!;
  assert.equal(
    triggers.bars.reduce((sum, b) => sum + b.value, 0),
    16,
  );
});
