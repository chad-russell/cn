export interface Cell {
  row: number;
  col: number;
  letter: string;
}

export interface FoundWord {
  word: string;
  isSpecial: boolean;
  cells: Cell[];
}

export const GRID: string[][] = [
  ["", "Y", "S", "", "E", "A", ""],
  ["R", "L", "A", "H", "B", "R", "T"],
  ["L", "I", "L", "L", "A", "N", "E"],
  ["", "A", "E", "T", "I", "D", ""],
  ["", "", "V", "N", "R", "", ""],
  ["", "", "", "I", "", "", ""],
];

export const SPECIAL_WORDS = [
  "HEATED",
  "RIVALRY",
  "SHANE",
  "ILYA",
  "HEART",
  "VALENTINE",
  "DALLAS",
] as const;

export type SpecialWord = typeof SPECIAL_WORDS[number];

export const DIRECTIONS: [number, number][] = [
  [-1, 0], [-1, 1], [0, 1], [1, 1],
  [1, 0], [1, -1], [0, -1], [-1, -1]
];
