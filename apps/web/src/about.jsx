import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import About from './pages/About.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <About />
  </StrictMode>,
)
