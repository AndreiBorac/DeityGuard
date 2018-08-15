/*
  libaboon/bignum.c
  copyright (c) 2017 by andrei borac
*/

#ifndef LB_BIGNUM_DIGIT_T
#define LB_BIGNUM_DIGIT_T uint64_t
#endif

#ifndef LB_BIGNUM_DIGIT_M_T
#define LB_BIGNUM_DIGIT_M_T __uint128_t
#endif

#define LB_BIGNUM_DIGIT_BITS   (sizeof(LB_BIGNUM_DIGIT_T)   << 3)
#define LB_BIGNUM_DIGIT_BITS_M (sizeof(LB_BIGNUM_DIGIT_M_T) << 3)

LB_TYPEBOTH(lb_bignum_t)
{
  uintptr_t          len;
  LB_BIGNUM_DIGIT_T* arr; /* little endian */
};

static LB_INLINE uintptr_t lbi_bignum_digits(uintptr_t bits)
{
  return ((bits + (LB_BIGNUM_DIGIT_BITS - 1)) / LB_BIGNUM_DIGIT_BITS);
}

static lb_bignum_t* lb_bignum_create(uintptr_t bits, lb_alloc_t* ac)
{
  LB_ALLOC_DECL(lb_bignum_t, bn, ac);
  
  bn->len = ((bits + (LB_BIGNUM_DIGIT_BITS - 1)) / LB_BIGNUM_DIGIT_BITS);
  
  uintptr_t siz = (bn->len * (LB_BIGNUM_DIGIT_BITS / 8));
  
  bn->arr = ((uintptr_t*)(lb_alloc(ac, siz)));
  
  return bn;
}

static void lb_bignum_delete(lb_bignum_t* bn, lb_alloc_t* ac)
{
  lb_alloc_free(ac, bn->arr, (bn->len * (LB_BIGNUM_DIGIT_BITS / 8)));
  
  LB_ALLOC_FREE(bn, ac);
}

static void lb_bignum_print(lb_bignum_t* bn)
{
  lb_print("sus", "bn->len=", bn->len, "\n");
  
  for (uintptr_t i = 0; i < bn->len; i++) {
    lb_print("susus", "bn->arr[", i, "]=", bn->arr[i], "\n");
  }
}

static void lb_bignum_set_lo(lb_bignum_t* bn, uintptr_t lo)
{
  bn->arr[0] = lo;
}

static void lb_bignum_reinit(lb_bignum_t* bn, uintptr_t v)
{
  lb_memset(bn->arr, 0, (bn->len * (LB_BIGNUM_DIGIT_BITS / 8)));
  
  lb_bignum_set_lo(bn, v);
}

static bool lb_bignum_is_zero(lb_bignum_t* bn)
{
  for (uintptr_t i = 0; i < bn->len; i++) {
    if (bn->arr[i] != 0) {
      return false;
    }
  }
  
  return true;
}

static bool lb_bignum_logical_get_bit(lb_bignum_t* bn, uintptr_t index)
{
  LB_ASSURE((index < (bn->len * LB_BIGNUM_DIGIT_BITS)));
  
  return ((bn->arr[(index / LB_BIGNUM_DIGIT_BITS)] & (((LB_BIGNUM_DIGIT_T)(1)) << (index % LB_BIGNUM_DIGIT_BITS))) != 0);
}

static void lb_bignum_logical_set_bit(lb_bignum_t* bn, uintptr_t index)
{
  LB_ASSURE((index < (bn->len * LB_BIGNUM_DIGIT_BITS)));
  
  bn->arr[(index / LB_BIGNUM_DIGIT_BITS)] |= (((LB_BIGNUM_DIGIT_T)(1)) << (index % LB_BIGNUM_DIGIT_BITS));
}

static uintptr_t lb_bignum_top_bit(lb_bignum_t* bn)
{
  uintptr_t best = -1UL;
  
  for (uintptr_t i = 0, l = (bn->len * LB_BIGNUM_DIGIT_BITS); i < l; i++) {
    if (lb_bignum_logical_get_bit(bn, i)) {
      best = i;
    }
  }
  
  return best;
}

#define LBI_CHECK_LEN LB_ASSURE((acc->len >= val->len));
#define LBI_COMMON_LEN uintptr_t com = LB_MIN(acc->len, val->len);

static void lb_bignum_mov_trunc(lb_bignum_t* acc, lb_bignum_t* val)
{
  LBI_COMMON_LEN;
  
  uintptr_t i = 0;
  
  for (; i < com; i++) {
    acc->arr[i] = val->arr[i];
  }
  
  for (; i < acc->len; i++) {
    acc->arr[i] = 0;
  }
}

static LB_INLINE void lb_bignum_mov(lb_bignum_t* acc, lb_bignum_t* val)
{
  LBI_CHECK_LEN;
  
  return lb_bignum_mov_trunc(acc, val);
}

#define LBI_BIGNUM_ITERATION(op)                                        \
  bool overflow = false;                                                \
                                                                        \
  void iteration(uintptr_t i, uintptr_t b)                              \
  {                                                                     \
    uintptr_t a = acc->arr[i];                                          \
                                                                        \
    bool overflow1, overflow2;                                          \
                                                                        \
    {                                                                   \
      if (overflow) {                                                   \
        LB_BIGNUM_DIGIT_T a_;                                           \
        overflow1 = __builtin_##op##_overflow(a, 1, (&(a_)));           \
        a = a_;                                                         \
      } else {                                                          \
        overflow1 = false;                                              \
      }                                                                 \
    }                                                                   \
                                                                        \
    LB_BIGNUM_DIGIT_T a_;                                               \
    overflow2 = __builtin_##op##_overflow(a, b, (&(a_)));               \
    acc->arr[i] = a_;                                                   \
                                                                        \
    LB_ASSURE((!(overflow1 && overflow2)));                             \
    overflow = (overflow1 | overflow2);                                 \
  }
  

static void lb_bignum_add(lb_bignum_t* acc, lb_bignum_t* val)
{
  //LBI_CHECK_LEN;
  LBI_COMMON_LEN;
  
  LBI_BIGNUM_ITERATION(add);
  
  {
    uintptr_t i = 0;
    
    for (; i < com; i++) {
      iteration(i, val->arr[i]);
    }
    
    for (; i < acc->len; i++) {
      iteration(i, 0);
      
      if (!(overflow)) {
        break;
      }
    }
  }
  
  LB_ASSURE((!(overflow)));
}

static void lb_bignum_sub(lb_bignum_t* acc, lb_bignum_t* val)
{
  //LBI_CHECK_LEN;
  LBI_COMMON_LEN;
  
  LBI_BIGNUM_ITERATION(sub);
  
  {
    uintptr_t i = 0;
    
    for (; i < com; i++) {
      iteration(i, val->arr[i]);
    }
    
    for (; i < acc->len; i++) {
      iteration(i, 0);
      
      if (!(overflow)) {
        break;
      }
    }
  }
  
  LB_ASSURE((!(overflow)));
}

static int lb_bignum_compare_signum(lb_bignum_t* a, lb_bignum_t* b)
{
  uintptr_t len = LB_MIN(a->len, b->len);
  
  /****/ if (a->len > b->len) {
    for (uintptr_t i = a->len; i-- > len;) {
      if (a->arr[i] != 0) {
        return +1;
      }
    }
  } else if (b->len > a->len) {
    for (uintptr_t i = b->len; i-- > len;) {
      if (b->arr[i] != 0) {
        return -1;
      }
    }
  }
  
  for (uintptr_t i = len; i-- > 0;) {
    /****/ if (a->arr[i] > b->arr[i]) {
      return +1;
    } else if (a->arr[i] < b->arr[i]) {
      return -1;
    }
  }
  
  return 00;
}

static bool lb_bignum_compare_eq(lb_bignum_t* a, lb_bignum_t* b)
{
  return (lb_bignum_compare_signum(a, b) == 0);
}

static bool lb_bignum_compare_le(lb_bignum_t* a, lb_bignum_t* b)
{
  return (lb_bignum_compare_signum(a, b) <= 0);
}

static bool lb_bignum_compare_ge(lb_bignum_t* a, lb_bignum_t* b)
{
  return (lb_bignum_compare_signum(a, b) >= 0);
}

static bool lb_bignum_compare_lt(lb_bignum_t* a, lb_bignum_t* b)
{
  return (lb_bignum_compare_signum(a, b) < 0);
}

static bool lb_bignum_compare_gt(lb_bignum_t* a, lb_bignum_t* b)
{
  return (lb_bignum_compare_signum(a, b) > 0);
}

#define LBI_BIGNUM_HI(x) (&((lb_bignum_t){ .len = ((x)->len - 1), .arr = ((x)->arr + 1), }))

/*
  mul(val, byx) = mul(val, ((byx_hi << bits) + byx_lo)) = ((mul(val, byx_hi) << bits) + mul_dgt(val, byx_lo))
*/

static void lbi_bignum_mul_dgt(lb_bignum_t* acc, uintptr_t dgt)
{
  LB_BIGNUM_DIGIT_T carry = 0;
  
#if 0
  lb_bignum_print(acc);
  LB_PV(dgt);
#endif
  
  for (uintptr_t i = 0; i < acc->len; i++) {
    LB_BIGNUM_DIGIT_M_T prd    = (((LB_BIGNUM_DIGIT_M_T)(acc->arr[i])) * ((LB_BIGNUM_DIGIT_M_T)(dgt)));
    LB_BIGNUM_DIGIT_T   prd_lo = ((LB_BIGNUM_DIGIT_T)(prd));
    LB_BIGNUM_DIGIT_T   prd_hi = ((LB_BIGNUM_DIGIT_T)(prd >> LB_BIGNUM_DIGIT_BITS));
    
    carry = prd_hi + (__builtin_add_overflow(prd_lo, carry, (&(acc->arr[i]))) ? 1 : 0);
  }
  
#if 0
  LB_PV(carry);
#endif
  
  LB_ASSURE_EQZ(carry);
}

static void lbi_bignum_mul_lvl(lb_bignum_t* acc, lb_bignum_t* val, lb_bignum_t* byx, lb_bignum_t* tmp)
{
  if (byx->len > 0) {
    /*
      recurse.
    */
    lbi_bignum_mul_lvl(LBI_BIGNUM_HI(acc), val, LBI_BIGNUM_HI(byx), LBI_BIGNUM_HI(tmp));
    
    /*
      addend.
    */
    {
      lb_bignum_mov_trunc(tmp, val);
      
      lbi_bignum_mul_dgt(tmp, byx->arr[0]);
      
      lb_bignum_add(acc, tmp);
    }
  }
}

/*
  try to make val <= byx to reduce the required size of the temporary.
  
  NOTE: actually, it seem the calculation for the required size of the
  temporary is not right; it apparently must be as long as the output
*/
static void lb_bignum_mul(lb_bignum_t* acc, lb_bignum_t* val, lb_bignum_t* byx, lb_bignum_t* tmp)
{
  LB_ASSURE((acc->len >= (val->len + byx->len)));
  LB_ASSURE((tmp->len >= (val->len + 1)));
  
  lbi_bignum_mul_lvl(acc, val, byx, tmp);
}

/*
  since our convention is little-endian, left-shift -really- means:
  - right-shift inter-word, but
  - left-shift intra-word
*/
static void lb_bignum_shl(lb_bignum_t* acc, uintptr_t sham)
{
  /*
    perform whole-word (inter-right) shifts first.
  */
  {
    uintptr_t whl = (sham / LB_BIGNUM_DIGIT_BITS);
    
    if (whl > 0) {
      sham -= (whl * LB_BIGNUM_DIGIT_BITS);
      
      uintptr_t i;
      
      for (i = acc->len; i-- > whl;) {
        acc->arr[i] = acc->arr[(i - whl)];
      }
      
      i++;
      
      for (; i-- > 0;) {
        acc->arr[i] = 0;
      }
    }
  }
  
  /*
    perform partial-word (intra-left, inter-right) shifts.
  */
  {
    if (sham > 0) {
      LB_BIGNUM_DIGIT_T carry = 0;
      
      for (uintptr_t i = 0; i < acc->len; i++) {
        uintptr_t x = acc->arr[i];
        
        LB_BIGNUM_DIGIT_T carry_next = (x >> (LB_BIGNUM_DIGIT_BITS - sham));
        
        x <<= sham;
        x  |= carry;
        
        acc->arr[i] = x;
        
        carry = carry_next;
      }
      
      LB_ASSURE_EQZ(carry);
    }
  }
}

/*
  since our convention is little-endian, right-shift -really- means:
  - left-shift inter-word, but
  - right-shift intra-word
*/
static void lb_bignum_shr(lb_bignum_t* acc, uintptr_t sham)
{
  /*
    perform whole-word (inter-left) shifts first.
  */
  {
    uintptr_t whl = (sham / LB_BIGNUM_DIGIT_BITS);
    
    if (whl > 0) {
      sham -= (whl * LB_BIGNUM_DIGIT_BITS);
      
      uintptr_t i;
      
      for (i = 0; i < (acc->len - whl); i++) {
        acc->arr[i] = acc->arr[(i + whl)];
      }
      
      for (; i < acc->len; i++) {
        acc->arr[i] = 0;
      }
    }
  }
  
  /*
    perform partial-word (intra-right, inter-left) shifts.
  */
  {
    if (sham > 0) {
      LB_BIGNUM_DIGIT_T carry = 0;
      
      for (uintptr_t i = acc->len; i-- > 0;) {
        uintptr_t x = acc->arr[i];
        
        LB_BIGNUM_DIGIT_T carry_next = (x & ((1UL << sham) - 1));
        
        x >>= sham;
        x  |= (carry << (LB_BIGNUM_DIGIT_BITS - sham));
        
        acc->arr[i] = x;
        
        carry = carry_next;
      }
      
      /*
        allow carry drop when right shifting. everyone expects right
        shift to be a lossy operation.
      */
      //LB_ASSURE_EQZ(carry);
    }
  }
}

static void lb_bignum_logical_and(lb_bignum_t* bn, lb_bignum_t* vl)
{
  uintptr_t len = LB_MIN(bn->len, vl->len);
  
  for (uintptr_t i = 0; i < len; i++) {
    bn->arr[i] &= vl->arr[i];
  }
}

/*
  the load/restore format is big-endian.
*/

static LB_BIGNUM_DIGIT_T lbi_hex2nib(char x)
{
  if (('0' <= x) && (x <= '9')) return LB_U((x - '0')     );
  if (('a' <= x) && (x <= 'f')) return LB_U((x - 'a') + 10);
  if (('A' <= x) && (x <= 'F')) return LB_U((x - 'A') + 10);
  
  LB_ILLEGAL;
}

static void lb_bignum_load(lb_bignum_t* bn, char* arr)
{
  for (uintptr_t i = bn->len; i-- > 0;) {
    LB_BIGNUM_DIGIT_T x = 0;
    
    for (uintptr_t j = 0; j < (LB_BIGNUM_DIGIT_BITS / 4); j++) {
      x <<= 4;
      x  |= (lbi_hex2nib((*(arr++))));
    }
    
    bn->arr[i] = x;
  }
}

static uintptr_t lb_bignum_save(lb_bignum_t* bn, char* arr)
{
  static char const nib2hex[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
  
  char const* arr_sav = arr;
  
  for (uintptr_t i = bn->len; i-- > 0;) {
    LB_BIGNUM_DIGIT_T x = bn->arr[i];
    
    for (uintptr_t j = 0; j < (LB_BIGNUM_DIGIT_BITS / 4); j++) {
      arr[((LB_BIGNUM_DIGIT_BITS / 4) - j - 1)] = nib2hex[(x & 0x0F)];
      x >>= 4;
    }
    
    arr += (LB_BIGNUM_DIGIT_BITS / 4);
  }
  
  return LB_PTRDIF(arr, arr_sav);
}

static void lb_bignum_dump(lb_bignum_t* bn)
{
  char arr[bn->len * (LB_BIGNUM_DIGIT_BITS / 4) + 1];
  
  uintptr_t len = lb_bignum_save(bn, arr);
  
  arr[len] = '\0';
  
  lb_print("ss", arr, "\n");
}

static void lb_bignum_barrett_old(uintptr_t k, lb_bignum_t* x /* k+k */, lb_bignum_t* m /* k */, lb_bignum_t* u /* k+1 */, lb_bignum_t* r /* k */, lb_alloc_t* ac)
{
  LB_ASSURE((k % LB_BIGNUM_DIGIT_BITS) == 0);
  
  LB_ASSURE(x->len == lbi_bignum_digits(k+k));
  LB_ASSURE(m->len == lbi_bignum_digits(k  ));
  LB_ASSURE(u->len == lbi_bignum_digits(k+1));
  LB_ASSURE(r->len == lbi_bignum_digits(k  ));
  
  lb_bignum_t* tt = lb_bignum_create((k+1+k+k), ac);
  lb_bignum_t* q1 = lb_bignum_create((k+1+k+k), ac);
  lb_bignum_reinit(q1, 0);
  lb_bignum_mul(q1, u, x, tt);
  lb_bignum_shr(q1, (k+k));
  
  lb_bignum_t* q2 = lb_bignum_create((k+1+k+k+k), ac);
  lb_bignum_reinit(q2, 0);
  lb_bignum_mul(q2, m, q1, tt);
  
  lb_bignum_t* r1 = lb_bignum_create((k+k), ac);
  lb_bignum_mov_trunc(r1, x);
  lb_bignum_sub(r1, q2);
  
  while (!(lb_bignum_compare_lt(r1, m))) {
    lb_bignum_sub(r1, m);
  }
  
  lb_bignum_mov_trunc(r, r1);
  
  lb_bignum_delete(tt, ac);
  lb_bignum_delete(q1, ac);
  lb_bignum_delete(q2, ac);
  lb_bignum_delete(r1, ac);
}

static void lb_bignum_barrett(uintptr_t k, lb_bignum_t* x /* k+k */, lb_bignum_t* m /* k */, lb_bignum_t* u /* k+1 */, lb_bignum_t* r /* k */, lb_alloc_t* ac)
{
  LB_ASSURE((k % LB_BIGNUM_DIGIT_BITS) == 0);
  
  LB_ASSURE(x->len == lbi_bignum_digits(k+k));
  LB_ASSURE(m->len == lbi_bignum_digits(k  ));
  LB_ASSURE(u->len == lbi_bignum_digits(k+1));
  LB_ASSURE(r->len == lbi_bignum_digits(k  ));
  
  LB_BIGNUM_DIGIT_T const_1_a[] = { 1 };
  lb_bignum_t const_1 = ((lb_bignum_t){ .len = 1, .arr = const_1_a });
  
  lb_bignum_t* q1 = lb_bignum_create((k+k), ac);
  lb_bignum_mov(q1, x);
  lb_bignum_shr(q1, k);
  lb_bignum_t* q2 = lb_bignum_create((k+1), ac);
  lb_bignum_mov_trunc(q2, q1);
  lb_bignum_t* q3 = lb_bignum_create((k+k+(2*LB_BIGNUM_DIGIT_BITS)), ac);
  lb_bignum_t* tt = lb_bignum_create((k+k+(2*LB_BIGNUM_DIGIT_BITS)), ac);
  lb_bignum_reinit(q3, 0);
  //LB_PV(q3->len);
  //LB_PV(q2->len);
  //LB_PV(u->len);
  //LB_PV(tt->len);
  //LB_TR;
  lb_bignum_mul(q3, q2, u, tt);
  //LB_TR;
  lb_bignum_shr(q3, k);
  lb_bignum_mov_trunc(q2, q3);
  
  lb_bignum_t* pw = lb_bignum_create((k+3), ac);
  lb_bignum_reinit(pw, 0);
  lb_bignum_logical_set_bit(pw, (k+2));
  
  lb_bignum_t* mk = lb_bignum_create((k+3), ac);
  lb_bignum_mov(mk, pw);
  lb_bignum_sub(mk, (&(const_1)));
  
  lb_bignum_t* r1 = lb_bignum_create((k+2), ac);
  lb_bignum_mov(r1, r);
  lb_bignum_logical_and(r1, mk);
  
  lb_bignum_t* r2 = lb_bignum_create((k+k+(2*LB_BIGNUM_DIGIT_BITS)), ac);
  lb_bignum_reinit(r2, 0);
  //LB_PV(r2->len);
  //LB_PV(q2->len);
  //LB_PV(m->len);
  //LB_PV(tt->len);
  //LB_TR;
  lb_bignum_mul(r2, q2, m, tt);
  //LB_TR;
  lb_bignum_logical_and(r2, mk);
  
  if (!(lb_bignum_compare_gt(r1, r2))) {
    lb_bignum_add(r1, pw);
  }
  
  lb_bignum_sub(r1, r2);
  
  while (!(lb_bignum_compare_lt(r1, m))) {
    lb_bignum_sub(r1, m);
  }
  
  lb_bignum_mov_trunc(r, r1);
  
  lb_bignum_delete(q1, ac);
  lb_bignum_delete(q2, ac);
  lb_bignum_delete(q3, ac);
  lb_bignum_delete(tt, ac);
  lb_bignum_delete(pw, ac);
  lb_bignum_delete(mk, ac);
  lb_bignum_delete(r1, ac);
  lb_bignum_delete(r2, ac);
}

static void lb_bignum_modexp(uintptr_t k, lb_bignum_t* b /* k */, lb_bignum_t* e /* k */, lb_bignum_t* m /* k */, lb_bignum_t* u /* k+1 */, lb_bignum_t* r /* k */, lb_alloc_t* ac)
{
  LB_ASSURE((k % LB_BIGNUM_DIGIT_BITS) == 0);
  
  LB_ASSURE(b->len == lbi_bignum_digits(k  ));
  //LB_ASSURE(e->len == lbi_bignum_digits(k  )); // actually we have no particular requirements on e
  LB_ASSURE(m->len == lbi_bignum_digits(k  ));
  LB_ASSURE(u->len == lbi_bignum_digits(k+1));
  LB_ASSURE(r->len == lbi_bignum_digits(k  ));
  
  /* w holds the walking exponential */
  lb_bignum_t* w = lb_bignum_create(k, ac);
  lb_bignum_mov(w, b);
  
  /* y and z are temporaries */
  lb_bignum_t* y = lb_bignum_create((k+k), ac);
  lb_bignum_t* z = lb_bignum_create((k+k), ac);
  
  lb_bignum_reinit(r, 1);
  
  LB_ASSURE(!(lb_bignum_is_zero(e)));
  
  for (uintptr_t i = 0, l = lb_bignum_top_bit(e); i <= l; i++) {
    if (lb_bignum_logical_get_bit(e, i)) {
      lb_bignum_reinit(y, 0);
      lb_bignum_mul(y, r, w, z);
      lb_bignum_barrett(k, y, m, u, r, ac);
    }
    
    lb_bignum_reinit(y, 0);
    lb_bignum_mul(y, w, w, z);
    lb_bignum_barrett(k, y, m, u, w, ac);
    
    //LB_ASSURE(lb_bignum_compare_lt(w, m));
  }
  
  lb_bignum_delete(w, ac);
  lb_bignum_delete(y, ac);
  lb_bignum_delete(z, ac);
}

/*
  kq   = bits of q
  kp   = bits of p
  g_lo = generator
  p    = Schnorr group large prime
  u    = Barrett reduction factor for p
  y    = public key
  c    = signed token
  s    = signature
  r2c  = mapping function from random value to signing token
*/
static bool lb_bignum_schnorr_verify(uintptr_t kq, uintptr_t kp, uintptr_t g, lb_bignum_t* p /* kp */, lb_bignum_t* u /* kp+1 */, lb_bignum_t* y /* kp */, lb_bignum_t* c /* kq */, lb_bignum_t* s /* kq */, void (*r2c)(lb_bignum_t* r /* kp */, lb_bignum_t* c /* kq */), lb_alloc_t* ac)
{
  lb_bignum_t* gs = lb_bignum_create(kp, ac);
  lb_bignum_reinit(gs, g);
  lb_bignum_modexp(kp, gs, s, p, u, gs, ac);
  
  lb_bignum_t* yc = lb_bignum_create(kp, ac);
  lb_bignum_mov(yc, y);
  lb_bignum_modexp(kp, yc, c, p, u, yc, ac);
  
  lb_bignum_t* tt = lb_bignum_create((kp+kp), ac);
  lb_bignum_t* gc = lb_bignum_create((kp+kp), ac);
  lb_bignum_reinit(gc, 0);
#if 0
  lb_bignum_dump(gs);
  lb_bignum_dump(yc);
  lb_bignum_dump(gc);
  LB_PV(gs->len);
  LB_PV(yc->len);
#endif
  lb_bignum_mul(gc, gs, yc, tt);
  
  lb_bignum_t* n = lb_bignum_create(kp, ac);
  lb_bignum_barrett(kp, gc, p, u, n, ac);
  
  lb_bignum_t* o = lb_bignum_create(kq, ac);
  r2c(n, o);
  
  bool success = lb_bignum_compare_eq(o, c);
  
  lb_bignum_delete(gs, ac);
  lb_bignum_delete(yc, ac);
  lb_bignum_delete(tt, ac);
  lb_bignum_delete(gc, ac);
  lb_bignum_delete(n,  ac);
  lb_bignum_delete(o,  ac);
  
  return success;
}
