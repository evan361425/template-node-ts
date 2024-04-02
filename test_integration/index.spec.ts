import assert from 'node:assert';
import { describe, it } from 'node:test';
import { Calculator } from '../src/index.js';

describe('Calculator', function () {
  it('#add', function () {
    const calc = new Calculator();
    const expected = 4;

    const actual = calc.add(1, 3);

    assert.deepStrictEqual(expected, actual);
  });
});
