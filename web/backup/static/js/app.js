// Unforgettable Dictionary - Client-side JavaScript

(function() {
    'use strict';

    // Audio playback functionality
    function initAudioButtons() {
        const audioButtons = document.querySelectorAll('.audio-btn');

        audioButtons.forEach(button => {
            button.addEventListener('click', function() {
                const text = this.previousElementSibling?.textContent ||
                           this.closest('.pronunciation')?.querySelector('.phonetic')?.textContent ||
                           document.querySelector('.word-title')?.textContent;

                if (text) {
                    playText(text.trim());
                }
            });
        });
    }

    // Text-to-speech function
    function playText(text) {
        if ('speechSynthesis' in window) {
            // Cancel any ongoing speech
            speechSynthesis.cancel();

            const utterance = new SpeechSynthesisUtterance(text);
            utterance.rate = 0.8;
            utterance.pitch = 1.0;
            utterance.volume = 1.0;

            // Try to use a high-quality voice
            const voices = speechSynthesis.getVoices();
            const preferredVoice = voices.find(voice =>
                voice.lang.startsWith('en') && voice.localService
            );

            if (preferredVoice) {
                utterance.voice = preferredVoice;
            }

            speechSynthesis.speak(utterance);
        } else {
            console.log('Text-to-speech not supported');
        }
    }

    // Search functionality
    function initSearch() {
        const searchInput = document.getElementById('word-search');
        const searchBtn = document.getElementById('search-btn');

        if (searchInput && searchBtn) {
            // Search on Enter key
            searchInput.addEventListener('keypress', function(e) {
                if (e.key === 'Enter') {
                    performSearch();
                }
            });

            // Search on button click
            searchBtn.addEventListener('click', performSearch);

            // Auto-suggest as user types (simple)
            let searchTimeout;
            searchInput.addEventListener('input', function() {
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => {
                    showSearchSuggestions(this.value);
                }, 300);
            });
        }
    }

    function performSearch() {
        const searchInput = document.getElementById('word-search');
        const word = searchInput.value.trim().toLowerCase();

        if (word.length > 0) {
            // Navigate to word page
            const firstLetter = word[0];
            const wordUrl = `/words/${firstLetter}/${word}.html`;

            // Track search event
            if (typeof gtag !== 'undefined') {
                gtag('event', 'search', {
                    search_term: word
                });
            }

            window.location.href = wordUrl;
        }
    }

    function showSearchSuggestions(query) {
        // Simple client-side suggestion (in real implementation, this would be server-side)
        if (query.length < 2) return;

        // This is a placeholder - in production you'd want proper search suggestions
        console.log('Search suggestions for:', query);
    }

    // Filter functionality for letter pages
    function initWordFilter() {
        const filterInput = document.getElementById('filter-words');

        if (filterInput) {
            filterInput.addEventListener('input', function() {
                const filter = this.value.toLowerCase();
                const wordItems = document.querySelectorAll('.word-item');

                wordItems.forEach(item => {
                    const word = item.dataset.word ||
                               item.querySelector('h3 a')?.textContent?.toLowerCase();

                    if (word && word.includes(filter)) {
                        item.style.display = '';
                    } else {
                        item.style.display = 'none';
                    }
                });

                // Update URL with filter parameter
                const url = new URL(window.location);
                if (filter) {
                    url.searchParams.set('filter', filter);
                } else {
                    url.searchParams.delete('filter');
                }
                history.replaceState(null, '', url);
            });

            // Restore filter from URL
            const urlParams = new URLSearchParams(window.location.search);
            const existingFilter = urlParams.get('filter');
            if (existingFilter) {
                filterInput.value = existingFilter;
                filterInput.dispatchEvent(new Event('input'));
            }
        }
    }

    // Lazy loading for images (if any)
    function initLazyLoading() {
        if ('IntersectionObserver' in window) {
            const imageObserver = new IntersectionObserver((entries, observer) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const img = entry.target;
                        img.src = img.dataset.src;
                        img.classList.remove('lazy');
                        imageObserver.unobserve(img);
                    }
                });
            });

            document.querySelectorAll('img[data-src]').forEach(img => {
                imageObserver.observe(img);
            });
        }
    }

    // Performance monitoring
    function initPerformanceTracking() {
        // Track Core Web Vitals
        if ('web-vital' in window) {
            // This would be imported from web-vitals library in production
            console.log('Performance tracking initialized');
        }

        // Track page load time
        window.addEventListener('load', function() {
            const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;

            if (typeof gtag !== 'undefined') {
                gtag('event', 'timing_complete', {
                    name: 'page_load',
                    value: loadTime
                });
            }
        });
    }

    // Analytics tracking for user interactions
    function initAnalytics() {
        // Track word page views
        if (window.location.pathname.includes('/words/')) {
            const word = document.querySelector('.word-title')?.textContent;
            if (word && typeof gtag !== 'undefined') {
                gtag('event', 'word_view', {
                    word_name: word.toLowerCase(),
                    page_path: window.location.pathname
                });
            }
        }

        // Track external link clicks
        document.querySelectorAll('a[target="_blank"]').forEach(link => {
            link.addEventListener('click', function() {
                if (typeof gtag !== 'undefined') {
                    gtag('event', 'external_link_click', {
                        link_url: this.href,
                        link_text: this.textContent
                    });
                }
            });
        });
    }

    // Keyboard navigation
    function initKeyboardNavigation() {
        document.addEventListener('keydown', function(e) {
            // Quick search with '/' key
            if (e.key === '/' && !e.ctrlKey && !e.metaKey) {
                const searchInput = document.getElementById('word-search') ||
                                 document.getElementById('filter-words');
                if (searchInput) {
                    e.preventDefault();
                    searchInput.focus();
                }
            }

            // Navigate between words with arrow keys
            if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                const navLinks = document.querySelectorAll('.word-navigation .nav-link');
                if (navLinks.length > 0) {
                    const link = e.key === 'ArrowLeft' ? navLinks[0] : navLinks[navLinks.length - 1];
                    if (link && e.altKey) {
                        e.preventDefault();
                        window.location.href = link.href;
                    }
                }
            }
        });
    }

    // Initialize all functionality when DOM is ready
    function init() {
        initAudioButtons();
        initSearch();
        initWordFilter();
        initLazyLoading();
        initPerformanceTracking();
        initAnalytics();
        initKeyboardNavigation();

        // Load voices for speech synthesis
        if ('speechSynthesis' in window) {
            speechSynthesis.addEventListener('voiceschanged', function() {
                // Voices loaded, ready for use
            });
        }
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // Service Worker registration (for PWA features)
    if ('serviceWorker' in navigator) {
        window.addEventListener('load', function() {
            navigator.serviceWorker.register('/sw.js')
                .then(function(registration) {
                    console.log('SW registered: ', registration);
                })
                .catch(function(registrationError) {
                    console.log('SW registration failed: ', registrationError);
                });
        });
    }

})();