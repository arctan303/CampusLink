import * as drcom from './drcom-http.uc';
import * as mock from './mock.uc';
import * as srun from './srun-srbx1.uc';
import * as ruijie from './ruijie-eportal.uc';

// One explicit registry for daemon validation and worker dispatch.
export const handlers = {'drcom-http':drcom, mock, 'srun-srbx1':srun, 'ruijie-eportal':ruijie};
