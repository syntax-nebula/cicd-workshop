# [2.0.0](https://example.com/home/ec2-user/remotes/cicd-workshop/compare/v1.0.0...v2.0.0) (2026-10-03)


* feat(events)!: remove the deprecated total field (contract phase) ([bb9df08](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/bb9df085b32a9caad06f436be2338db4f44088d8))


### Bug Fixes

* **events:** restore the OrderPlaced detail-type in the rule ([956aaeb](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/956aaebe470afa7224fd20b67de9a25fe3968d53))
* **iam:** restore DynamoDB write permission on the orders table ([7c060c9](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/7c060c968027979ec401547486388fc4c8493569))
* restore correct secrets module path ([9132049](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/9132049e3176251a917f0ef7ff816c7d0bf414d9))
* **security:** add fulfilment DLQ and PITR; document VPC exemption ([6bdd589](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/6bdd589f72844d2d71d9e2467af4109e04ab382c))
* **security:** resolve payment credentials from Secrets Manager at runtime ([b1722c8](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/b1722c800883f5fc11f7d782c1f352cf7447661f))


### Features

* add payment API key (DO NOT DO THIS) ([b2fb248](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/b2fb248c97e2762195074020cfe234149db02275))
* complete event-driven reference application ([f16369a](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/f16369a187015b477559c78b90e40851521c65fb))
* **deploy:** add PreTraffic smoke-test hook ([1ccf390](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/1ccf390bf7d07af095dea3f5b9c349d2e0ae973e))
* **deploy:** canary preference with version-scoped alarms ([9cfbab5](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/9cfbab52c010daf4b7ec79cecc0f847adfd854ff))
* **deploy:** publish versions and a live alias ([19422ce](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/19422ce6f254cdfa391b1c1a851b7853291a5c9c))
* **events:** publish orderTotal alongside total (expand phase) ([4b02103](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/4b021034d43ed8abb7c1853c864fdedf17fe9397))
* **fulfilment:** read orderTotal with a fallback to total (migrate phase) ([aced1dc](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/aced1dc2a255b5fe605794909fafc21b695d70c8))
* **iac:** parameterise the template by environment ([878c1f6](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/878c1f6f747e728df33c8dd24a6e42e76c3e570d))
* **order-api:** include apiVersion in validation errors ([f90e16e](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/f90e16e649392aa869cf1dff57556ac1e53dfc84))


### BREAKING CHANGES

* OrderPlaced no longer includes `total`. Consumers must read
`orderTotal`. All consumers listed in docs/events.md were migrated in the
previous release and read `orderTotal` with a fallback, so this deployment is
safe for them. Any consumer NOT in that catalogue will silently receive
undefined - which is precisely why the catalogue is mandatory.

Refs: docs/events.md

# [1.0.0](https://example.com/home/ec2-user/remotes/cicd-workshop/compare/1dd9011719c3f26eca92f337b0a34f746582ff7b...v1.0.0) (2026-10-02)


* feat(events)!: rename OrderPlaced.customer to customerId ([3943780](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/3943780ccdcda9ff5d59149933682bdb9bb81246))


### Bug Fixes

* **order-api:** raise timeout to 30 seconds for slow downstream ([e83f190](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/e83f1904de31462f6707a68d3ded3ea7b61862ce))
* **order-api:** reject non-array items payload ([9fc783c](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/9fc783c802db075ebf9bc0a4a43b2a7ac2febbf8))


### Features

* **events:** add event bus and fulfilment handler ([1dd9011](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/1dd9011719c3f26eca92f337b0a34f746582ff7b))
* **order-api:** flag high-value orders ([a9196d2](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/a9196d2f2265a91f3279b8d201e827f56a36d2bb))


### Performance Improvements

* **order-api:** reduce timeout to 5 seconds ([13d0d75](https://example.com/home/ec2-user/remotes/cicd-workshop/commits/13d0d7596c642b92980e2fb75936c2a3306e94be))


### BREAKING CHANGES

* consumers reading `customer` must be updated before this
is deployed to prod.
