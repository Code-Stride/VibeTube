// ===== Initialize Lucide Icons =====
document.addEventListener('DOMContentLoaded', () => {
    lucide.createIcons();
    initParticles();
    initNavbar();
    initFAQ();
    initAnimations();
});

// ===== Particles Animation =====
function initParticles() {
    const container = document.getElementById('particles');
    if (!container) return;
    
    for (let i = 0; i < 50; i++) {
        const particle = document.createElement('div');
        particle.className = 'particle';
        particle.style.left = Math.random() * 100 + '%';
        particle.style.top = Math.random() * 100 + '%';
        particle.style.animationDelay = Math.random() * 20 + 's';
        particle.style.animationDuration = (15 + Math.random() * 20) + 's';
        particle.style.width = (2 + Math.random() * 4) + 'px';
        particle.style.height = particle.style.width;
        container.appendChild(particle);
    }
}

// ===== Navbar Scroll Effect =====
function initNavbar() {
    const navbar = document.getElementById('navbar');
    if (!navbar) return;

    let lastScroll = 0;

    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset;
        
        if (currentScroll > 50) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
        
        lastScroll = currentScroll;
    });

    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });
}

// ===== FAQ Accordion =====
function initFAQ() {
    const faqItems = document.querySelectorAll('.faq-item');
    
    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');
        
        question.addEventListener('click', () => {
            const isActive = item.classList.contains('active');
            
            // Close all items
            faqItems.forEach(i => i.classList.remove('active'));
            
            // Open clicked item if it was closed
            if (!isActive) {
                item.classList.add('active');
            }
        });
    });
}

// ===== Scroll Animations =====
function initAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate-in');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe elements
    const animateElements = document.querySelectorAll(
        '.feature-card, .screenshot-card, .faq-item, .tech-item, .download-card, .sb-content'
    );
    
    animateElements.forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });
}

// ===== Add animate-in class styles =====
const style = document.createElement('style');
style.textContent = `
    .animate-in {
        opacity: 1 !important;
        transform: translateY(0) !important;
    }
`;
document.head.appendChild(style);

// ===== Download Counter =====
function incrementDownloadCount() {
    let count = localStorage.getItem('vibetube_downloads') || 0;
    count = parseInt(count) + 1;
    localStorage.setItem('vibetube_downloads', count);
    return count;
}

// Track download clicks
document.addEventListener('click', (e) => {
    const downloadBtn = e.target.closest('[href*="download"]');
    if (downloadBtn && downloadBtn.href.includes('.apk')) {
        incrementDownloadCount();
        
        // Show download started notification
        showNotification('Download started! Check your downloads folder.');
    }
});

// ===== Notification System =====
function showNotification(message) {
    const notification = document.createElement('div');
    notification.style.cssText = `
        position: fixed;
        bottom: 24px;
        right: 24px;
        background: linear-gradient(135deg, #FF6B6B, #4ECDC4);
        color: white;
        padding: 16px 24px;
        border-radius: 12px;
        font-size: 14px;
        font-weight: 600;
        box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        z-index: 10000;
        animation: slideIn 0.3s ease;
        display: flex;
        align-items: center;
        gap: 10px;
    `;
    
    notification.innerHTML = `
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
            <polyline points="22 4 12 14.01 9 11.01"></polyline>
        </svg>
        ${message}
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease forwards';
        setTimeout(() => notification.remove(), 300);
    }, 3000);
}

// ===== Add animation keyframes =====
const animStyle = document.createElement('style');
animStyle.textContent = `
    @keyframes slideIn {
        from {
            transform: translateX(100%);
            opacity: 0;
        }
        to {
            transform: translateX(0);
            opacity: 1;
        }
    }
    
    @keyframes slideOut {
        from {
            transform: translateX(0);
            opacity: 1;
        }
        to {
            transform: translateX(100%);
            opacity: 0;
        }
    }
`;
document.head.appendChild(animStyle);

// ===== Copy to Clipboard =====
function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        showNotification('Copied to clipboard!');
    }).catch(err => {
        console.error('Failed to copy: ', err);
    });
}

// ===== Version Check =====
async function checkLatestVersion() {
    try {
        const response = await fetch('https://api.github.com/repos/Code-Stride/VibeTube/releases/latest');
        const data = await response.json();
        
        if (data.tag_name) {
            const versionBadge = document.querySelector('.hero-badge span');
            if (versionBadge) {
                versionBadge.textContent = `${data.tag_name} • Free & Open Source`;
            }
            
            // Update download links if release assets exist
            if (data.assets && data.assets.length > 0) {
                const releaseApk = data.assets.find(a => a.name.includes('release'));
                const debugApk = data.assets.find(a => a.name.includes('debug'));
                
                if (releaseApk) {
                    document.querySelectorAll('a[href*="release.apk"]').forEach(link => {
                        link.href = releaseApk.browser_download_url;
                    });
                }
                if (debugApk) {
                    document.querySelectorAll('a[href*="debug.apk"]').forEach(link => {
                        link.href = debugApk.browser_download_url;
                    });
                }
            }
        }
    } catch (error) {
        console.log('Could not fetch latest version');
    }
}

// Check version on load
checkLatestVersion();

// ===== Floating Download Button =====
const floatingDownload = document.getElementById('floatingDownload');
if (floatingDownload) {
    window.addEventListener('scroll', () => {
        if (window.scrollY > 500) {
            floatingDownload.style.display = 'flex';
        } else {
            floatingDownload.style.display = 'none';
        }
    });
    
    // Initially hide
    floatingDownload.style.display = 'none';
}
