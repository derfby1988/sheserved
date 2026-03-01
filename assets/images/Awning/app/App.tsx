import { DartBoard } from './components/DartBoard';

export default function App() {
  return (
    <div className="size-full flex items-center justify-center bg-gradient-to-br from-gray-50 to-gray-100 overflow-auto">
      <DartBoard />
    </div>
  );
}