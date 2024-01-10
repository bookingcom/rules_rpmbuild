def deduplicate_rpms(needed, existing):
    existing = dict([ (x.split("//:", 1)[1], 1) for x in existing ])
    out = [x for x in needed if x.split("//:", 1)[1] not in existing]
    return out
