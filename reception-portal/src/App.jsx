import { useState } from 'react'

function App() {
  const [name, setName] = useState('')
  const [condition, setCondition] = useState('')
  const [status, setStatus] = useState({ type: '', message: '' })
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()

    if (!name.trim() || !condition.trim()) {
      setStatus({ type: 'error', message: 'Please fill in all fields' })
      return
    }

    setIsSubmitting(true)
    setStatus({ type: '', message: '' })

    try {
      const response = await fetch('/admit', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ name: name.trim(), condition: condition.trim() }),
      })

      const data = await response.json()

      if (response.ok) {
        setStatus({
          type: 'success',
          message: `Patient "${name}" admitted successfully. ID: ${data.patientId}`
        })
        setName('')
        setCondition('')
      } else {
        setStatus({
          type: 'error',
          message: data.error || 'Failed to admit patient'
        })
      }
    } catch (error) {
      setStatus({
        type: 'error',
        message: 'Connection error. Please try again.'
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="container">
      <header className="header">
        <div className="logo">
          <svg viewBox="0 0 24 24" className="logo-icon">
            <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-1 11h-4v4h-4v-4H6v-4h4V6h4v4h4v4z"/>
          </svg>
          <h1>MediQueue</h1>
        </div>
        <p className="subtitle">Reception Portal</p>
      </header>

      <main className="main">
        <div className="card">
          <h2>Patient Admission</h2>
          <p className="card-description">
            Enter patient details to add them to the waiting queue
          </p>

          <form onSubmit={handleSubmit} className="form">
            <div className="form-group">
              <label htmlFor="name">Patient Name</label>
              <input
                type="text"
                id="name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Enter patient's full name"
                disabled={isSubmitting}
              />
            </div>

            <div className="form-group">
              <label htmlFor="condition">Condition</label>
              <textarea
                id="condition"
                value={condition}
                onChange={(e) => setCondition(e.target.value)}
                placeholder="Describe the patient's condition"
                rows={3}
                disabled={isSubmitting}
              />
            </div>

            <button
              type="submit"
              className="submit-btn"
              disabled={isSubmitting}
            >
              {isSubmitting ? (
                <>
                  <span className="spinner"></span>
                  Admitting...
                </>
              ) : (
                'Admit Patient'
              )}
            </button>
          </form>

          {status.message && (
            <div className={`status ${status.type}`}>
              {status.type === 'success' ? (
                <svg viewBox="0 0 24 24" className="status-icon">
                  <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" className="status-icon">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
                </svg>
              )}
              <span>{status.message}</span>
            </div>
          )}
        </div>
      </main>

      <footer className="footer">
        <p>Queue/Worker Pattern Demo</p>
      </footer>
    </div>
  )
}

export default App
