import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import confetti from 'canvas-confetti'
import { SPECIAL_WORDS, GRID, type Cell, type FoundWord } from './game/types'
import { isSpecialWord, isValidBonusWord, isValidWord } from './game/grid'
import { WordBoard } from './components/WordBoard'

const TUTORIAL_STORAGE_KEY = 'stumpdle-tutorial-seen'
const PROGRESS_STORAGE_KEY = 'stumpdle-progress'
const PARTY_DURATION_MS = 5000
const PARTY_FADE_OUT_MS = 850
const PARTY_EMOJIS = ['💖', '❤️', '😍', '🍆', '🍑', '💘']

type TutorialExample = {
  targetWord: string
  hint: string
  letters: string[][]
}

const TUTORIAL_EXAMPLES: TutorialExample[] = [
  {
    targetWord: 'ILOVECHAD',
    hint: 'Find the hidden word by dragging across connected letters.',
    letters: [
      ['', 'L', 'O', ''],
      ['I', 'E', 'V', ''],
      ['', '', 'C', 'A'],
      ['', '', 'D', 'H'],
    ],
  },
]

function App() {
  const [foundWords, setFoundWords] = useState<FoundWord[]>([])
  const [message, setMessage] = useState<string | null>(null)
  const [showTutorial, setShowTutorial] = useState(false)
  const [tutorialStep, setTutorialStep] = useState(0)
  const [tutorialSolved, setTutorialSolved] = useState<Record<number, boolean>>({})
  const [tutorialSolvedPaths, setTutorialSolvedPaths] = useState<Record<number, Cell[]>>({})
  const [tutorialMessage, setTutorialMessage] = useState<string | null>(null)
  const [tutorialMessageTone, setTutorialMessageTone] = useState<'success' | 'error'>('error')
  const [showParty, setShowParty] = useState(false)
  const [partyFadingOut, setPartyFadingOut] = useState(false)
  const partyStopTimeoutRef = useRef<number | null>(null)
  const partyBurstIntervalRef = useRef<number | null>(null)
  const partyFadeTimeoutRef = useRef<number | null>(null)
  const prevHasWonRef = useRef(false)

  const foundWordsSet = useMemo(() => new Set(foundWords.map(fw => fw.word)), [foundWords])

  useEffect(() => {
    const tutorialSeen = localStorage.getItem(TUTORIAL_STORAGE_KEY)
    if (!tutorialSeen) {
      setShowTutorial(true)
    }

    const savedProgress = localStorage.getItem(PROGRESS_STORAGE_KEY)
    if (savedProgress) {
      try {
        const parsed = JSON.parse(savedProgress) as FoundWord[]
        setFoundWords(parsed)
      } catch {
      }
    }
  }, [])

  const specialWordsFound = foundWords.filter(fw => fw.isSpecial)
  const bonusWordsFound = foundWords.filter(fw => !fw.isSpecial)
  const hasWon = specialWordsFound.length === SPECIAL_WORDS.length

  const partyDrops = useMemo(() => {
    return Array.from({ length: 42 }, (_, idx) => ({
      id: idx,
      emoji: PARTY_EMOJIS[idx % PARTY_EMOJIS.length],
      left: Math.random() * 100,
      delay: Math.random() * 0.9,
      duration: 2.2 + Math.random() * 1.8,
      size: 22 + Math.random() * 20,
      rotate: -25 + Math.random() * 50,
    }))
  }, [])

  const stopParty = useCallback((withFadeOut = false) => {
    if (partyBurstIntervalRef.current) {
      window.clearInterval(partyBurstIntervalRef.current)
      partyBurstIntervalRef.current = null
    }
    if (partyStopTimeoutRef.current) {
      window.clearTimeout(partyStopTimeoutRef.current)
      partyStopTimeoutRef.current = null
    }
    if (partyFadeTimeoutRef.current) {
      window.clearTimeout(partyFadeTimeoutRef.current)
      partyFadeTimeoutRef.current = null
    }

    if (withFadeOut) {
      setPartyFadingOut(true)
      partyFadeTimeoutRef.current = window.setTimeout(() => {
        setShowParty(false)
        setPartyFadingOut(false)
        confetti.reset()
        partyFadeTimeoutRef.current = null
      }, PARTY_FADE_OUT_MS)
      return
    }

    setPartyFadingOut(false)
    setShowParty(false)
    confetti.reset()
  }, [])

  const triggerParty = useCallback(() => {
    stopParty()
    setShowParty(true)
    const isMobile = window.matchMedia('(max-width: 768px)').matches
    const particleCount = isMobile ? 34 : 62
    const endTime = Date.now() + PARTY_DURATION_MS

    const launchBurst = () => {
      if (Date.now() >= endTime) {
        stopParty(true)
        return
      }

      confetti({
        particleCount,
        spread: 95,
        startVelocity: isMobile ? 26 : 32,
        ticks: isMobile ? 130 : 170,
        disableForReducedMotion: false,
        origin: {
          x: 0.15 + Math.random() * 0.7,
          y: 0.42 + Math.random() * 0.25,
        },
        colors: ['#f43f5e', '#fb7185', '#ec4899', '#f472b6', '#fda4af'],
      })
    }

    launchBurst()
    partyBurstIntervalRef.current = window.setInterval(launchBurst, isMobile ? 280 : 220)
    partyStopTimeoutRef.current = window.setTimeout(() => stopParty(true), PARTY_DURATION_MS)
  }, [stopParty])

  useEffect(() => {
    if (hasWon && !prevHasWonRef.current) {
      triggerParty()
    }
    prevHasWonRef.current = hasWon
  }, [hasWon, triggerParty])

  useEffect(() => {
    return () => {
      stopParty()
    }
  }, [stopParty])

  useEffect(() => {
    if (foundWords.length > 0) {
      localStorage.setItem(PROGRESS_STORAGE_KEY, JSON.stringify(foundWords))
    }
  }, [foundWords])

  const flashGameMessage = (text: string, timeout = 1500) => {
    setMessage(text)
    window.setTimeout(() => setMessage(null), timeout)
  }

  const flashTutorialMessage = (text: string, timeout = 1500) => {
    setTutorialMessageTone('error')
    setTutorialMessage(text)
    window.setTimeout(() => setTutorialMessage(null), timeout)
  }

  const handleMainWordSubmit = (upperWord: string, cells: Cell[]) => {
    if (foundWordsSet.has(upperWord)) {
      flashGameMessage('Already found!', 1000)
      return
    }

    if (isSpecialWord(upperWord)) {
      setFoundWords(prev => [...prev, { word: upperWord, isSpecial: true, cells: [...cells] }])
      flashGameMessage('🎉 Special word!')
      return
    }

    if (isValidBonusWord(upperWord) || isValidWord(upperWord)) {
      setFoundWords(prev => [...prev, { word: upperWord, isSpecial: false, cells: [...cells] }])
      flashGameMessage('✨ Bonus word!')
      return
    }

    flashGameMessage('Not a valid word')
  }

  const openTutorial = () => {
    setTutorialStep(0)
    setTutorialSolved({})
    setTutorialSolvedPaths({})
    setTutorialMessage(null)
    setTutorialMessageTone('error')
    setShowTutorial(true)
  }

  const closeTutorial = () => {
    localStorage.setItem(TUTORIAL_STORAGE_KEY, 'true')
    setShowTutorial(false)
    setTutorialStep(0)
    setTutorialSolved({})
    setTutorialSolvedPaths({})
    setTutorialMessage(null)
    setTutorialMessageTone('error')
  }

  const currentTutorial = TUTORIAL_EXAMPLES[tutorialStep]
  const currentStepSolved = Boolean(tutorialSolved[tutorialStep])

  const handleTutorialWordSubmit = (upperWord: string, cells: Cell[]) => {
    if (upperWord !== currentTutorial.targetWord) {
      flashTutorialMessage('Not quite. Keep trying on this board.')
      return
    }

    setTutorialSolved(prev => ({ ...prev, [tutorialStep]: true }))
    setTutorialSolvedPaths(prev => ({ ...prev, [tutorialStep]: cells }))
    setTutorialMessageTone('success')
    setTutorialMessage('Nice! You solved the tutorial')
  }

  return (
    <div className="h-dvh overflow-hidden bg-gray-50 flex flex-col items-center py-8 px-4">
      {showParty && (
        <div
          className={`
            fixed inset-0 z-[60] pointer-events-none overflow-hidden transition-opacity
            ${partyFadingOut ? 'opacity-0' : 'opacity-100'}
          `}
          style={{ transitionDuration: `${PARTY_FADE_OUT_MS}ms` }}
        >
          <div className="absolute inset-0 bg-gradient-to-b from-rose-400/25 via-pink-300/20 to-fuchsia-400/25" />
          {partyDrops.map(drop => (
            <span
              key={drop.id}
              className="party-emoji-drop absolute -top-12"
              style={{
                left: `${drop.left}%`,
                animationDelay: `${drop.delay}s`,
                animationDuration: `${drop.duration}s`,
                fontSize: `${drop.size}px`,
                '--party-rotate': `${drop.rotate}deg`,
              } as CSSProperties}
            >
              {drop.emoji}
            </span>
          ))}
          <div className="absolute inset-x-0 top-20 flex justify-center px-4">
            <div className="rounded-3xl bg-white/90 shadow-2xl border border-rose-200 px-6 py-4 text-center">
              <p className="text-3xl mb-1">💖😍🍆🍑😍💖</p>
              <p className="text-2xl font-black text-rose-600">You Found All 7!</p>
              <p className="text-sm font-semibold text-rose-500">LOVE YOU BABE 😘</p>
            </div>
          </div>
        </div>
      )}

      {showTutorial && (
        <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-[1px] flex items-center justify-center p-4">
          <div className="w-full max-w-md bg-white rounded-2xl shadow-2xl p-5 sm:p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-xl font-bold text-gray-900">How To Play</h2>
            </div>

            <p className="text-sm text-gray-600 mb-3">
              Drag across touching letters to spell words. Letters connect horizontally,
              vertically, or diagonally.
            </p>

            <div className="bg-emerald-500 text-white rounded-xl px-4 py-3 text-center font-medium mb-4">
              {currentTutorial.hint}
            </div>

            <WordBoard
              key={`tutorial-board-${tutorialStep}`}
              grid={currentTutorial.letters}
              onWordSubmit={(word, cells) => handleTutorialWordSubmit(word, cells)}
              solvedPathCells={tutorialSolvedPaths[tutorialStep] ?? []}
              className="bg-gray-50 rounded-2xl p-3 mb-4"
              cellSizeClassName="w-14 h-14 sm:w-16 sm:h-16"
            />

            {tutorialMessage && (
              <p
                className={`
                  text-center text-sm font-semibold mb-3
                  ${tutorialMessageTone === 'success' ? 'text-emerald-600' : 'text-rose-600'}
                `}
              >
                {tutorialMessage}
              </p>
            )}

            <div className="flex gap-2">
              <button
                type="button"
                className="flex-1 rounded-xl px-4 py-2.5 bg-gray-200 text-gray-700 font-semibold hover:bg-gray-300 transition-colors"
                onClick={closeTutorial}
              >
                Close
              </button>

              {tutorialStep < TUTORIAL_EXAMPLES.length - 1 ? (
                <button
                  type="button"
                  disabled={!currentStepSolved}
                  className={`
                    flex-1 rounded-xl px-4 py-2.5 font-semibold transition-colors
                    ${currentStepSolved
                      ? 'bg-rose-500 text-white hover:bg-rose-600'
                      : 'bg-rose-200 text-rose-100 cursor-not-allowed'
                    }
                  `}
                  onClick={() => setTutorialStep(prev => prev + 1)}
                >
                  Next
                </button>
              ) : (
                <button
                  type="button"
                  disabled={!currentStepSolved}
                  className={`
                    flex-1 rounded-xl px-4 py-2.5 font-semibold transition-colors
                    ${currentStepSolved
                      ? 'bg-rose-500 text-white hover:bg-rose-600'
                      : 'bg-rose-200 text-rose-100 cursor-not-allowed'
                    }
                  `}
                  onClick={closeTutorial}
                >
                  Start Game
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      <div className="fixed top-4 right-4 z-40 flex items-center gap-2">
        <button
          type="button"
          className="rounded-full bg-white/95 shadow-md border border-gray-200 px-3 py-1.5 text-sm font-semibold text-gray-700 hover:bg-gray-100"
          onClick={openTutorial}
        >
          How to Play
        </button>
      </div>

      <h1 className="text-3xl font-bold text-gray-800 mb-2 shrink-0">Stumpdle</h1>
      <p className="text-gray-500 mb-6 text-sm shrink-0">Find all the hidden words</p>

      {message && (
        <div className="fixed top-8 left-1/2 -translate-x-1/2 bg-white shadow-lg rounded-full px-6 py-3 text-lg font-medium z-50 animate-bounce">
          {message}
        </div>
      )}

      <WordBoard
        grid={GRID}
        onWordSubmit={handleMainWordSubmit}
        className="bg-white rounded-2xl shadow-lg p-4 mb-6 shrink-0"
      />

      <div className="w-full max-w-md flex-1 min-h-0 overflow-y-auto overscroll-contain px-1 pb-4">
        <div className="space-y-6">
          <div>
            <h2 className="text-lg font-semibold text-gray-700 mb-3">
              Special Words ({specialWordsFound.length}/{SPECIAL_WORDS.length})
            </h2>
            <div className="flex flex-wrap gap-2">
              {SPECIAL_WORDS.map(word => {
                const found = foundWordsSet.has(word)
                return (
                  <span
                    key={word}
                    className={`
                      px-3 py-1.5 rounded-full text-sm font-medium
                      ${found
                        ? 'bg-rose-500 text-white'
                        : 'bg-gray-200 text-gray-400'
                      }
                    `}
                  >
                    {found ? word : '•••••'}
                  </span>
                )
              })}
              {hasWon && (
                <button
                  type="button"
                  className="px-3 py-1.5 rounded-full text-sm font-medium bg-rose-100 text-rose-700 border border-rose-300 hover:bg-rose-200"
                  onClick={triggerParty}
                >
                  Replay Party
                </button>
              )}
            </div>
          </div>

          <div>
            <h2 className="text-lg font-semibold text-gray-700 mb-3">
              Bonus Words ({bonusWordsFound.length})
            </h2>
            <div className="flex flex-wrap gap-2">
              {bonusWordsFound.map(fw => (
                <span
                  key={fw.word}
                  className="px-3 py-1.5 rounded-full text-sm font-medium bg-emerald-100 text-emerald-700"
                >
                  {fw.word}
                </span>
              ))}
              {bonusWordsFound.length === 0 && (
                <span className="text-gray-400 text-sm">Find bonus words to see them here</span>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default App
