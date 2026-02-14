import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { Cell } from '../game/types'
import { cellsToWord } from '../game/grid'

type WordBoardProps = {
  grid: string[][]
  onWordSubmit: (word: string, cells: Cell[]) => void
  className?: string
  cellSizeClassName?: string
  solvedPathCells?: Cell[]
  solvedPathColor?: string
}

export function WordBoard({
  grid,
  onWordSubmit,
  className = '',
  cellSizeClassName = 'w-12 h-12 sm:w-14 sm:h-14',
  solvedPathCells = [],
  solvedPathColor = 'rgba(34, 197, 94, 0.7)',
}: WordBoardProps) {
  const [selectedCells, setSelectedCells] = useState<Cell[]>([])
  const [isSelecting, setIsSelecting] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)
  const cellRefs = useRef<Map<string, HTMLDivElement>>(new Map())

  const columnCount = useMemo(
    () => Math.max(...grid.map(row => row.length)),
    [grid]
  )

  const handleStart = useCallback((row: number, col: number) => {
    if (!grid[row]?.[col]) return
    setIsSelecting(true)
    setSelectedCells([{ row, col, letter: grid[row][col] }])
  }, [grid])

  const handleMove = useCallback((row: number, col: number) => {
    if (!isSelecting) return
    if (!grid[row]?.[col]) return

    setSelectedCells(prev => {
      const lastCell = prev[prev.length - 1]
      if (!lastCell) return prev

      const targetIsCurrent = lastCell.row === row && lastCell.col === col
      if (targetIsCurrent) return prev

      const previousCell = prev[prev.length - 2]
      const targetIsPrevious =
        previousCell?.row === row && previousCell?.col === col
      if (targetIsPrevious) {
        return prev.slice(0, -1)
      }

      const alreadySelected = prev.some(c => c.row === row && c.col === col)
      if (alreadySelected) return prev

      const rowDiff = Math.abs(lastCell.row - row)
      const colDiff = Math.abs(lastCell.col - col)
      if (rowDiff > 1 || colDiff > 1) return prev

      return [...prev, { row, col, letter: grid[row][col] }]
    })
  }, [isSelecting, grid])

  const handleEnd = useCallback(() => {
    if (!isSelecting) return
    setIsSelecting(false)

    if (selectedCells.length < 2) {
      setSelectedCells([])
      return
    }

    onWordSubmit(cellsToWord(selectedCells).toUpperCase(), [...selectedCells])
    setSelectedCells([])
  }, [isSelecting, selectedCells, onWordSubmit])

  useEffect(() => {
    const handleGlobalEnd = () => {
      if (isSelecting) {
        handleEnd()
      }
    }

    window.addEventListener('mouseup', handleGlobalEnd)
    window.addEventListener('touchend', handleGlobalEnd)
    return () => {
      window.removeEventListener('mouseup', handleGlobalEnd)
      window.removeEventListener('touchend', handleGlobalEnd)
    }
  }, [isSelecting, handleEnd])

  const getCellPosition = (row: number, col: number): { x: number; y: number } | null => {
    const key = `${row}-${col}`
    const cell = cellRefs.current.get(key)
    const container = containerRef.current
    if (!cell || !container) return null

    const cellRect = cell.getBoundingClientRect()
    const containerRect = container.getBoundingClientRect()
    return {
      x: cellRect.left + cellRect.width / 2 - containerRect.left,
      y: cellRect.top + cellRect.height / 2 - containerRect.top,
    }
  }

  const renderPath = (cells: Cell[], color: string) => {
    if (cells.length < 2) return null
    const pathParts: string[] = []
    for (let i = 0; i < cells.length; i++) {
      const pos = getCellPosition(cells[i].row, cells[i].col)
      if (!pos) continue

      if (i === 0) {
        pathParts.push(`M ${pos.x} ${pos.y}`)
      } else {
        pathParts.push(`L ${pos.x} ${pos.y}`)
      }
    }

    return (
      <svg className="absolute inset-0 pointer-events-none z-20 w-full h-full">
        <path
          d={pathParts.join(' ')}
          fill="none"
          stroke={color}
          strokeWidth="4"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    )
  }

  return (
    <div ref={containerRef} className={`relative touch-none ${className}`}>
      <div className="flex justify-center">
        <div className="inline-grid gap-2" style={{ gridTemplateColumns: `repeat(${columnCount}, auto)` }}>
          {grid.map((row, rowIdx) =>
            Array.from({ length: columnCount }, (_, colIdx) => {
              const cell = row[colIdx] ?? ''
              if (!cell) {
                return (
                  <div
                    key={`${rowIdx}-${colIdx}`}
                    className={`${cellSizeClassName} pointer-events-none`}
                    aria-hidden="true"
                  />
                )
              }

              const isSelected = selectedCells.some(c => c.row === rowIdx && c.col === colIdx)
              const isStart = selectedCells[0]?.row === rowIdx && selectedCells[0]?.col === colIdx

              return (
                <div
                  key={`${rowIdx}-${colIdx}`}
                  ref={(el) => {
                    if (el) {
                      cellRefs.current.set(`${rowIdx}-${colIdx}`, el)
                    } else {
                      cellRefs.current.delete(`${rowIdx}-${colIdx}`)
                    }
                  }}
                  className={`
                    ${cellSizeClassName} flex items-center justify-center
                    text-xl font-bold rounded-lg cursor-pointer select-none
                    transition-all duration-100
                    ${isSelected
                      ? 'bg-rose-500 text-white scale-110 shadow-lg'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }
                    ${isStart ? 'ring-2 ring-rose-300 ring-offset-2' : ''}
                  `}
                  onMouseDown={() => handleStart(rowIdx, colIdx)}
                  onMouseEnter={() => handleMove(rowIdx, colIdx)}
                  onTouchStart={(e) => {
                    e.preventDefault()
                    handleStart(rowIdx, colIdx)
                  }}
                  onTouchMove={(e) => {
                    e.preventDefault()
                    const touch = e.touches[0]
                    const element = document.elementFromPoint(touch.clientX, touch.clientY)
                    if (!element) return

                    const key = element.getAttribute('data-cell-key')
                    if (!key) return

                    const [r, c] = key.split('-').map(Number)
                    handleMove(r, c)
                  }}
                  data-cell-key={`${rowIdx}-${colIdx}`}
                >
                  {cell}
                </div>
              )
            })
          )}
        </div>
      </div>
      {selectedCells.length >= 2
        ? renderPath(selectedCells, 'rgba(244, 63, 94, 0.6)')
        : renderPath(solvedPathCells, solvedPathColor)}
    </div>
  )
}
