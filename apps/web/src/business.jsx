import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import Business from './pages/Business.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Business />
  </StrictMode>,
)
