/*
  libaboon/divide.c
  copyright (c) 2017 by andrei borac
*/

#ifdef LB_ARCH_HAS_DIV_64

static uint32_t lb_div_64_by_32(uint64_t divend, uint32_t divsor, uint64_t* divquo)
{
  if (divquo) {
    *divquo = (divend / divsor);
  }
  
  return ((uint32_t)(divend % divsor));
}

#else

#if 0

static uint32_t lb_div_64_by_32(uint64_t divend, uint32_t divsor, uint64_t* divquo)
{
  uint64_t outquo = 0;
  
  while (divend > divsor) {
    divend -= divsor;
    outquo++;
  }
  
  if (divquo) {
    *divquo = outquo;
  }
  
  return ((uint32_t)(divend));
}

#endif

static uint32_t lb_div_64_by_32(uint64_t divend, uint32_t divsor, uint64_t* divquo)
{
  uint64_t sormul[64];
  
  sormul[0] = divsor;
  
  uintptr_t sorlen = LB_ARRLEN(sormul);
  
  for (uintptr_t i = 1; i < LB_ARRLEN(sormul); i++) {
    uint64_t prvmul = sormul[(i-1)];
    uint64_t nexmul = (prvmul << 1);
    
    if ((nexmul >> 1) != (prvmul)) {
      sorlen = i;
      break;
    }
    
    sormul[i] = nexmul;
  }
  
  uint64_t outquo = 0;
  
  while ((sorlen--) != 0) {
    while (divend >= sormul[sorlen]) {
      divend -= sormul[sorlen];
      outquo += (((uint64_t)(1)) << sorlen);
    }
  }
  
  if (divquo) {
    *divquo = outquo;
  }
  
  return ((uint32_t)(divend));
}

#endif
