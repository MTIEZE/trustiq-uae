import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import Trust from './pages/Trust.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Trust />
  </StrictMode>,
)
