/*
  libaboon/alloc.c
  copyright (c) 2017 by andrei borac
*/

#ifndef LB_MAXIMUM_ALIGNMENT
#define LB_MAXIMUM_ALIGNMENT 8UL
#endif

#ifndef LB_SBRK_INCREMENT
#define LB_SBRK_INCREMENT 65536
#endif

#ifndef LB_ALLOC_BINS
#define LB_ALLOC_BINS 64
#endif

typedef struct
{
  uint8_t*  rbrk;
  uint8_t*  cbrk;
  uintptr_t left;
}
lb_sbrk_t;

static void lb_sbrk_initialize(lb_sbrk_t* sb)
{
  sb->rbrk = sb->cbrk = LB_PV(((uint8_t*)(LBT_OK(lbt_brk(0)))));
  sb->left = 0;
}

static void* lb_sbrk(lb_sbrk_t* sb, uintptr_t size)
{
  LB_PV(size);
  
  size += ( (LB_MAXIMUM_ALIGNMENT - 1));
  size &= (~(LB_MAXIMUM_ALIGNMENT - 1));
  
  LB_PV(size);
  
  while (size > sb->left) {
    LB_ASSURE(((uint8_t*)(lbt_brk(0))) == sb->rbrk);
    sb->rbrk += LB_SBRK_INCREMENT;
    LB_ASSURE((LB_UI(lbt_brk(LB_U(sb->rbrk))) == LB_U(sb->rbrk)));
    sb->left += LB_SBRK_INCREMENT;
  }
  
  void* retv = sb->cbrk;
  sb->cbrk += size;
  sb->left -= size;
  return retv;
}

#define LBI_H(x) (*((void**)(x)))

typedef struct
{
  lb_sbrk_t* sb;
  
  void* head[LB_ALLOC_BINS];
}
lb_alloc_t;

static void lb_alloc_initialize(lb_alloc_t* ac, lb_sbrk_t* sb)
{
  ac->sb = sb;
  
  LB_BZERO((ac->head));
}

#if 0

static uintptr_t lb_alloc_bin(uintptr_t* size)
{
  uintptr_t bin = 0;
  uintptr_t val = sizeof(uintptr_t); // can't alloc less than a pointer!
  
  while (val < (*size)) {
    bin++;
    val <<= 1;
  }
  
  LB_PV((*size));
  LB_PV(bin);
  LB_PV(val);
  
  *size = val;
  
  return bin;
}

#else

/*
  WARNING: doesn't do the right thing when size is zero.
*/
static LB_INLINE uintptr_t lb_alloc_bin(uintptr_t* size)
{
  uintptr_t bsr = lb_bsr(((*size) - 1));
  
  *size = (1UL << (bsr + 1));
  
  return bsr;
}

#endif

#define LBI_ALLOC_PROLOGUE                                              \
  /* we can't deliver less than a pointer's worth ... because we need a pointer for the free list */ \
  {                                                                     \
    if (size < sizeof(void*)) {                                         \
      size = sizeof(void*);                                             \
    }                                                                   \
  }                                                                     \
                                                                        \
  uintptr_t bin = lb_alloc_bin(&size);                                  \
                                                                        \
  /* check that we didn't end up out of bounds with the bin somehow */  \
  LB_ASSURE((bin < LB_ARRLEN(ac->head)));                               \
                                                                        \
  void** head = &(ac->head[bin]);

static void* lb_alloc(lb_alloc_t* ac, uintptr_t size)
{
  LBI_ALLOC_PROLOGUE;
  
  if (*head) {
    void* retv = *head;
    *head = LBI_H(*head);
    
    LB_DG("susus", "lb_alloc: old: ", LB_U(retv), " (", size, ")\n");
    return retv;
  } else {
    void* retv = lb_sbrk(ac->sb, size);
    
    /* check that we are delivering on alignment */
    LB_ASSURE(((((uintptr_t)(retv)) & (LB_MAXIMUM_ALIGNMENT - 1)) == 0));
    
    LB_DG("susus", "lb_alloc: new: ", LB_U(retv), " (", size, ")\n");
    return retv;
  }
}

static void lb_alloc_free(lb_alloc_t* ac, void* mem, uintptr_t size)
{
  LBI_ALLOC_PROLOGUE;
  
  LB_DG("susus", "lb_alloc_free: ", LB_U(mem), " (", size, ")\n");
  
  LBI_H(mem) = *head;
  *head = mem;
}

#define LB_ALLOC_DECL(t, v, ac) t* v = ((t*)(lb_alloc((ac), sizeof(t))))
#define LB_ALLOC_FREE(v, ac) lb_alloc_free((ac), (v), sizeof((*(v))))

typedef struct { void** head; } lb_alloc_direct_t;

static lb_alloc_direct_t lb_alloc_direct(lb_alloc_t* ac, uintptr_t size)
{
  LBI_ALLOC_PROLOGUE;
  
  return ((lb_alloc_direct_t){ .head = head });
}

static LB_INLINE void* lb_alloc_direct_alloc(lb_alloc_direct_t ad, uintptr_t size, lb_alloc_t* ac)
{
  if ((*(ad.head))) {
    void* retv = (*(ad.head));
    (*(ad.head)) = LBI_H((*(ad.head)));
    LB_DG("susus", "lb_alloc_direct_alloc: old: ", LB_U(retv), " (", size, ")\n");
    return retv;
  } else {
    return lb_alloc(ac, size);
  }
}

static LB_INLINE void lb_alloc_direct_free(lb_alloc_direct_t ad, void* mem)
{
  LB_DG("sus", "lb_alloc_direct_free: ", LB_U(mem), " (?)\n");
  LBI_H(mem) = (*(ad.head));
  (*(ad.head)) = mem;
}
