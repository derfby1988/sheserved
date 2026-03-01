import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import dartImage from 'figma:asset/2042b341fc900430764bda6c5d7cc3f7cab2c055.png';

interface Dart {
  id: number;
  x: number;
  y: number;
  score: number;
}

export function DartBoard() {
  const [darts, setDarts] = useState<Dart[]>([]);
  const [totalScore, setTotalScore] = useState(0);
  const [dartsLeft, setDartsLeft] = useState(3);
  const [throwingDart, setThrowingDart] = useState<{ x: number; y: number } | null>(null);

  const calculateScore = (x: number, y: number, boardSize: number) => {
    const centerX = boardSize / 2;
    const centerY = boardSize / 2;
    const distance = Math.sqrt(Math.pow(x - centerX, 2) + Math.pow(y - centerY, 2));
    const maxRadius = boardSize / 2;

    if (distance < maxRadius * 0.1) return 50; // Bullseye
    if (distance < maxRadius * 0.25) return 25; // Inner ring
    if (distance < maxRadius * 0.5) return 15; // Middle ring
    if (distance < maxRadius * 0.75) return 10; // Outer ring
    if (distance < maxRadius) return 5; // Edge
    return 0; // Missed
  };

  const handleBoardClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (dartsLeft <= 0) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const boardSize = rect.width;

    setThrowingDart({ x, y });

    setTimeout(() => {
      const score = calculateScore(x, y, boardSize);
      const newDart: Dart = {
        id: Date.now(),
        x,
        y,
        score,
      };

      setDarts((prev) => [...prev, newDart]);
      setTotalScore((prev) => prev + score);
      setDartsLeft((prev) => prev - 1);
      setThrowingDart(null);
    }, 600);
  };

  const resetGame = () => {
    setDarts([]);
    setTotalScore(0);
    setDartsLeft(3);
    setThrowingDart(null);
  };

  return (
    <div className="flex flex-col items-center gap-6 p-8">
      <div className="text-center">
        <h1 className="text-4xl font-bold mb-2">Dart Game</h1>
        <p className="text-lg text-gray-600">Click on the board to throw your darts!</p>
      </div>

      <div className="flex gap-12 items-start">
        <div className="flex flex-col gap-4">
          <div className="bg-white rounded-lg shadow-lg p-6 min-w-[200px]">
            <div className="text-center mb-4">
              <div className="text-5xl font-bold text-blue-600">{totalScore}</div>
              <div className="text-sm text-gray-500 uppercase tracking-wide">Total Score</div>
            </div>
            <div className="border-t pt-4">
              <div className="text-2xl font-semibold text-center mb-1">{dartsLeft}</div>
              <div className="text-sm text-gray-500 uppercase tracking-wide text-center">
                Darts Left
              </div>
            </div>
          </div>

          <button
            onClick={resetGame}
            className="bg-green-600 hover:bg-green-700 text-white font-semibold py-3 px-6 rounded-lg transition-colors"
          >
            New Game
          </button>

          <div className="bg-gray-100 rounded-lg p-4">
            <h3 className="font-semibold mb-2 text-sm">Scoring:</h3>
            <div className="text-xs space-y-1 text-gray-700">
              <div className="flex justify-between">
                <span>🎯 Bullseye:</span>
                <span className="font-semibold">50 pts</span>
              </div>
              <div className="flex justify-between">
                <span>🔴 Inner Ring:</span>
                <span className="font-semibold">25 pts</span>
              </div>
              <div className="flex justify-between">
                <span>🟡 Middle Ring:</span>
                <span className="font-semibold">15 pts</span>
              </div>
              <div className="flex justify-between">
                <span>🟢 Outer Ring:</span>
                <span className="font-semibold">10 pts</span>
              </div>
              <div className="flex justify-between">
                <span>🔵 Edge:</span>
                <span className="font-semibold">5 pts</span>
              </div>
            </div>
          </div>
        </div>

        <div className="relative">
          <div
            onClick={handleBoardClick}
            className={`relative bg-gradient-to-br from-slate-800 to-slate-900 rounded-full shadow-2xl ${
              dartsLeft > 0 ? 'cursor-crosshair' : 'cursor-not-allowed'
            }`}
            style={{
              width: '500px',
              height: '500px',
            }}
          >
            {/* Dartboard rings */}
            <div className="absolute inset-0 rounded-full overflow-hidden">
              <div className="absolute inset-[5%] rounded-full bg-blue-500 opacity-20" />
              <div className="absolute inset-[25%] rounded-full bg-green-500 opacity-30" />
              <div className="absolute inset-[40%] rounded-full bg-yellow-500 opacity-40" />
              <div className="absolute inset-[45%] rounded-full bg-red-500 opacity-50" />
              <div className="absolute inset-[47.5%] rounded-full bg-red-600 shadow-inner" />
            </div>

            {/* Lines for sections */}
            {[...Array(20)].map((_, i) => {
              const angle = (i * 18 * Math.PI) / 180;
              return (
                <div
                  key={i}
                  className="absolute bg-black opacity-10"
                  style={{
                    width: '2px',
                    height: '50%',
                    left: '50%',
                    top: '0',
                    transformOrigin: 'bottom center',
                    transform: `rotate(${i * 18}deg)`,
                  }}
                />
              );
            })}

            {/* Thrown darts */}
            <AnimatePresence>
              {darts.map((dart) => (
                <motion.div
                  key={dart.id}
                  initial={{ scale: 0, rotate: -45 }}
                  animate={{ scale: 1, rotate: 0 }}
                  className="absolute"
                  style={{
                    left: `${dart.x}px`,
                    top: `${dart.y}px`,
                    transform: 'translate(-50%, -50%)',
                  }}
                >
                  <img
                    src={dartImage}
                    alt="dart"
                    className="w-12 h-12 drop-shadow-lg"
                    style={{ transform: 'rotate(180deg)' }}
                  />
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    className="absolute -top-8 left-1/2 -translate-x-1/2 bg-white px-2 py-1 rounded shadow-lg text-xs font-bold"
                  >
                    +{dart.score}
                  </motion.div>
                </motion.div>
              ))}
            </AnimatePresence>

            {/* Throwing animation */}
            {throwingDart && (
              <motion.div
                initial={{ x: -100, y: 500, scale: 0.5, opacity: 0 }}
                animate={{
                  x: throwingDart.x,
                  y: throwingDart.y,
                  scale: 1,
                  opacity: 1,
                }}
                transition={{ duration: 0.6, ease: 'easeOut' }}
                className="absolute"
                style={{
                  transform: 'translate(-50%, -50%)',
                }}
              >
                <img
                  src={dartImage}
                  alt="dart"
                  className="w-12 h-12"
                  style={{ transform: 'rotate(180deg)' }}
                />
              </motion.div>
            )}

            {dartsLeft === 0 && (
              <div className="absolute inset-0 bg-black bg-opacity-50 rounded-full flex items-center justify-center">
                <div className="bg-white p-6 rounded-lg text-center">
                  <div className="text-3xl font-bold mb-2">Game Over!</div>
                  <div className="text-xl mb-4">Final Score: {totalScore}</div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      resetGame();
                    }}
                    className="bg-green-600 hover:bg-green-700 text-white font-semibold py-2 px-6 rounded-lg transition-colors"
                  >
                    Play Again
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow p-4 max-w-[700px]">
        <h3 className="font-semibold mb-2">Your Throws:</h3>
        <div className="flex gap-2 flex-wrap">
          {darts.length === 0 ? (
            <p className="text-gray-400 text-sm">No darts thrown yet</p>
          ) : (
            darts.map((dart, index) => (
              <div
                key={dart.id}
                className="bg-gray-100 px-3 py-1 rounded text-sm font-medium"
              >
                Dart {index + 1}: {dart.score} pts
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
