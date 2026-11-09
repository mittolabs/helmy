// Reveal on scroll. Cheap, and it stops a long page reading as one
// undifferentiated slab.
const seen = new IntersectionObserver(
  (entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add("in");
        seen.unobserve(e.target);
      }
    }
  },
  { rootMargin: "0px 0px -12% 0px", threshold: 0.05 },
);
document.querySelectorAll(".reveal").forEach((el, i) => {
  el.style.transitionDelay = `${Math.min(i % 4, 3) * 70}ms`;
  seen.observe(el);
});
