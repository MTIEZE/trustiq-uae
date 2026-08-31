import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import Download from './pages/Download.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Download />
  </StrictMode>,
)
