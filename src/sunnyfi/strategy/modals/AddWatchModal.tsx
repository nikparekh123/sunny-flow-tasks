import { useState } from 'react';
import { Modal } from './Modal';

interface Props {
  onClose: () => void;
  onConfirm: (p: {
    ticker: string;
    name: string;
    sector: string;
    current_price: number;
  }) => void;
}

export function AddWatchModal({ onClose, onConfirm }: Props) {
  const [ticker, setTicker] = useState('');
  const [name, setName] = useState('');
  const [sector, setSector] = useState('');
  const [px, setPx] = useState(100);

  return (
    <Modal onClose={onClose}>
      <div className="mh">
        <div>
          <div className="sub">watchlist</div>
          <div className="title">Add ticker</div>
        </div>
        <button className="x" onClick={onClose}>✕</button>
      </div>

      <div className="form-grid">
        <div className="field">
          <label>Ticker</label>
          <input
            type="text"
            value={ticker}
            onChange={(e) => setTicker(e.target.value.toUpperCase())}
            placeholder="AMD"
            autoFocus
          />
        </div>
        <div className="field">
          <label>Sector</label>
          <input
            type="text"
            value={sector}
            onChange={(e) => setSector(e.target.value)}
            placeholder="Tech"
          />
        </div>
        <div className="field full">
          <label>Name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Advanced Micro Devices"
          />
        </div>
        <div className="field">
          <label>Current price</label>
          <input
            type="number"
            step="0.01"
            value={px}
            onChange={(e) => setPx(parseFloat(e.target.value || '0'))}
          />
        </div>
      </div>

      <div className="actions">
        <div />
        <div className="group">
          <button className="btn ghost" onClick={onClose}>cancel</button>
          <button
            className="btn primary"
            disabled={!ticker}
            onClick={() =>
              onConfirm({
                ticker,
                name: name || ticker,
                sector: sector || '—',
                current_price: px,
              })
            }
          >
            ✓ add to watchlist
          </button>
        </div>
      </div>
    </Modal>
  );
}
