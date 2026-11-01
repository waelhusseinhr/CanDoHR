import assert from "node:assert/strict";
import test from "node:test";
import { CanDoError, Money } from "../src/index.ts";

test("money parses two-decimal strings and rejects JavaScript numbers", () => {
  assert.equal(Money.parse("72000").toString(), "72000.00");
  assert.equal(Money.parse("10.5").toString(), "10.50");
  assert.equal(Money.parse("-0.00").toString(), "0.00");
  assert.equal(Money.parse("0.10").plus(Money.parse("0.20")).toString(), "0.30");
  assert.equal(Money.parse("10.00").times("1.5").toString(), "15.00");
  assert.equal(Money.parse("1.25").times("0.5").toString(), "0.62");
  assert.throws(
    () => Money.parse(1.1 as unknown as string),
    (error: CanDoError) => error.code === "MONEY_FORMAT",
  );
  assert.throws(() => Number(Money.parse("1.00")), (error: CanDoError) => error.code === "MONEY_NUMBER");
  assert.throws(() => Money.parse("1.234"), (error: CanDoError) => error.code === "MONEY_FORMAT");
  assert.throws(() => Money.parse("1000000000000.00"), (error: CanDoError) => error.code === "MONEY_FORMAT");
  assert.throws(() => Money.parse("10.00").times(2 as unknown as string), (error: CanDoError) => error.code === "MONEY_FORMAT");
});

test("money addition of one cent does not drift", () => {
  let amount = Money.parse("0.00");
  for (let i = 0; i < 10; i += 1) {
    amount = amount.plus(Money.parse("0.01"));
  }
  assert.equal(amount.toString(), "0.10");
  assert.equal(amount.minus(Money.parse("0.10")).toString(), "0.00");
});
