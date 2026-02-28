import { GRID, SPECIAL_WORDS, type Cell } from './types';
import { FINDABLE_WORDS } from './findable-words';

const FINDABLE_SET = new Set(FINDABLE_WORDS.map(w => w.toUpperCase()));

export function getNonEmptyCells(): Cell[] {
  const cells: Cell[] = [];
  for (let row = 0; row < GRID.length; row++) {
    for (let col = 0; col < GRID[row].length; col++) {
      if (GRID[row][col]) {
        cells.push({ row, col, letter: GRID[row][col] });
      }
    }
  }
  return cells;
}

export function areAdjacent(a: Cell, b: Cell): boolean {
  const rowDiff = Math.abs(a.row - b.row);
  const colDiff = Math.abs(a.col - b.col);
  return rowDiff <= 1 && colDiff <= 1 && !(rowDiff === 0 && colDiff === 0);
}

export function cellsToWord(cells: Cell[]): string {
  return cells.map(c => c.letter).join('');
}

export function isSpecialWord(word: string): boolean {
  return SPECIAL_WORDS.includes(word.toUpperCase() as typeof SPECIAL_WORDS[number]);
}

export function isValidBonusWord(word: string): boolean {
  const upper = word.toUpperCase();
  return FINDABLE_SET.has(upper) && !isSpecialWord(upper);
}

export function isValidWord(word: string): boolean {
  const upper = word.toUpperCase();
  return isSpecialWord(upper) || FINDABLE_SET.has(upper);
}

export function canFormWord(cells: Cell[], gridCells: Cell[]): boolean {
  if (cells.length < 2) return false;
  
  for (let i = 1; i < cells.length; i++) {
    if (!areAdjacent(cells[i - 1]!, cells[i]!)) {
      return false;
    }
  }
  
  for (const cell of cells) {
    if (!gridCells.some(gc => gc.row === cell.row && gc.col === cell.col)) {
      return false;
    }
  }
  
  return true;
}
