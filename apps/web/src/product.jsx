import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import Product from './pages/Product.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Product />
  </StrictMode>,
)
