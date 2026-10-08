/* global axios */
import ApiClient from './ApiClient';

class ReportExportsAPI extends ApiClient {
  constructor() {
    super('report_exports', { accountScoped: true });
  }

  download(id) {
    return axios.get(`${this.url}/${id}/download`, { responseType: 'blob' });
  }
}

export default new ReportExportsAPI();
